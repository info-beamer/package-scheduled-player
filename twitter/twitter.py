import re
import os
import sys
import time
import hashlib
import calendar
import traceback
from collections import namedtuple
from operator import itemgetter
from cStringIO import StringIO
from contextlib import closing

import requests
from hosted import node
from PIL import Image

blocked = set(line.strip() for line in open("blocked.txt") if line.strip())

Video = namedtuple("Video", "duration url")

def get_text(tweet):
    if hasattr(tweet, 'full_text'):
        return tweet.full_text
    else:
        return tweet.text

def extract_content(tweet):
    text = get_text(tweet)

    all_entities = tweet.entities.copy()
    if hasattr(tweet, 'extended_entities'):
        # import pprint
        # print text.encode("utf8")
        # pprint.pprint(tweet.extended_entities)
        all_entities.update(tweet.extended_entities)

    sorted_entities = []
    for etype, entities in all_entities.iteritems():
        for entity in entities:
            s, e = entity['indices']
            sorted_entities.append((s, e, etype, entity))
    sorted_entities.sort(reverse=True)

    def replace(str, s, e, new):
        return str[:s] + new + str[e:]

    images = []
    video = None

    for s, e, etype, entity in sorted_entities:
        if etype == 'media':
            text = replace(text, s, e, '')
            url = None
            for size in ('large', 'medium'): # try the preferred sizes
                size_info = entity['sizes'].get(size)
                if size_info and size_info['h'] < 2048 and size_info['w'] < 2048:
                    url = entity['media_url_https'] + ":" + size
                    break
            if url is None:
                url = entity['media_url_https']
            images.append(url)

            video_info = entity.get('video_info')
            if video_info:
                print >>sys.stderr, "got videos: %r" % (video_info,)
                duration = video_info['duration_millis'] / 1000. \
                    if 'duration_millis' in video_info else None

                usable_videos = []
                for variant in video_info['variants']:
                    if variant['content_type'] == 'video/mp4':
                        usable_videos.append((variant['bitrate'], variant['url']))
                usable_videos.sort(reverse=True) # highest bitrate first

                while len(usable_videos) >= 2:
                    highest_bitrate = usable_videos[0][0]
                    if highest_bitrate > 1000000:
                        print >>sys.stderr, "discarding variant with too high bitrate %d" % highest_bitrate
                        usable_videos.pop(0)
                    else:
                        break

                if usable_videos:
                    video = Video(duration, usable_videos[0][1])
        elif etype == 'urls':
            text = replace(text, s, e, entity['display_url'])

    # print sorted_entities
    # print images
    # why does twitter return html entities!?
    text = text.replace("&amp;", "&")
    text = text.replace("&lt;", "<")
    text = text.replace("&gt;", ">")

    return text, images, video

def cache_image(url, ext='jpg'):
    cache_name = 'cache-image-%s.%s' % (hashlib.md5(url).hexdigest(), ext)
    print >>sys.stderr, 'caching %s' % url
    if not os.path.exists(cache_name):
        try:
            r = requests.get(url, timeout=20)
            fobj = StringIO(r.content)
            im = Image.open(fobj) # test if it opens
            del fobj
            im.save(cache_name)
        except:
            traceback.print_exc()
            return
    return cache_name

def cache_video(url):
    cache_name = 'cache-video-%s.mp4' % hashlib.md5(url).hexdigest()
    print >>sys.stderr, 'caching %s' % url
    if not os.path.exists(cache_name):
        try:
            with closing(requests.get(url, stream=True, timeout=20)) as r:
                with open(cache_name, "wb") as out:
                    for chunk in r.iter_content(chunk_size = 2**16):
                        out.write(chunk)
        except:
            traceback.print_exc()
            return
    return cache_name

def cache_images(urls):
    cached_images = []
    for url in urls:
        cached = cache_image(url)
        if cached:
            cached_images.append(cached)
    return cached_images

def profile_image(url):
    # url = url.replace('normal', 'bigger')
    url = url.replace('normal', '200x200')
    image = cache_image(url, 'png')
    if not image:
        return 'default-profile.png'
    return image

def clean_whitespace(text):
    return re.sub("\s+", " ", text).strip()

def convert(tweet):
    text, images, video = extract_content(tweet)
    cached_images = cache_images(images)
    cached_video = cache_video(video.url) if video else None

    converted = dict(
        id = str(tweet.id),
        name = tweet.user.name,
        created_at = calendar.timegm(tweet.created_at.utctimetuple()),
        screen_name = tweet.user.screen_name,
        text = clean_whitespace(text),
        profile_image = profile_image(tweet.user.profile_image_url_https),
        images = cached_images,
    )

    if cached_video:
        converted['video'] = dict(
            filename = cached_video,
        )
        if video.duration:
            converted['video']['duration'] = video.duration
    return converted

def save_tweets(tweets):
    tweets = [convert(tweet) for tweet in tweets]
    tweets.sort(key=itemgetter("created_at"), reverse=True)
    node.write_json("tweets.json", tweets)

def is_tweet_garbage(tweet):
    if tweet.user.name in blocked:
        print >>sys.stderr, "GARBAGE: blocked user"
        return True

    if hasattr(tweet, 'retweeted_status'):
        print >>sys.stderr, "GARBAGE: ehh. retweet"
        return True

    if tweet.user.default_profile:
        print >>sys.stderr, "GARBAGE: Default profile"
        return True

    if tweet.user.default_profile_image:
        print >>sys.stderr, "GARBAGE: Default profile image"
        return True

    text = get_text(tweet)
    if len(text) < 10:
        print >>sys.stderr, "GARBAGE: Too short"
        return True

    if text.startswith("."):
        print >>sys.stderr, "GARBAGE: Dot tweet"
        return True

    if text.startswith("@"):
        print >>sys.stderr, "GARBAGE: starts with @"
        return True

    if text.startswith("RT "):
        print >>sys.stderr, "GARBAGE: starts with RT"
        return True

    if tweet.user.followers_count < 10:
        print >>sys.stderr, "GARBAGE: too few followers"
        return True

    if tweet.user.description is None:
        print >>sys.stderr, "GARBAGE: no description"
        return True

    return False

def filter_and_save(tweets, not_before, count, filter_garbage):
    print >>sys.stderr, "got %d tweets" % len(tweets)
    for tweet in tweets:
        print >>sys.stderr, "%s %s" % (
            tweet.created_at.date(), not_before
        )

    tweets = [
        tweet for tweet in tweets
        if tweet.created_at.date() >= not_before and
           (not filter_garbage or not is_tweet_garbage(tweet))
    ][:count]

    print >>sys.stderr, "handling %d tweets" % len(tweets)
    save_tweets(tweets)
    return tweets

def cleanup(max_age=12*3600):
    global blocked
    blocked = set(line.strip() for line in open("blocked.txt") if line.strip())
    now = time.time()
    for filename in os.listdir("."):
        if not filename.startswith('cache-'):
            continue
        age = now - os.path.getctime(filename)
        if age > max_age:
            try:
                os.unlink(filename)
            except:
                traceback.print_exc()
