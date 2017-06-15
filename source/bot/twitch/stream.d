module bot.twitch.stream;

import vibe.core.log;
import vibe.data.json;

import bot.twitch.api;
import bot.twitch.userids;

import std.conv;
import std.datetime;

struct LiveCache
{
	bool live;
	long channel;
	SysTime check;
}

bool isLive(string channel)
{
	if (!channel.length)
		return false;
	if (channel[0] == '#')
		channel = channel[1 .. $];
	if (!channel.length)
		return false;
	long id = useridFor(channel);
	bool hadPrevious, wasLive;
	foreach_reverse (i, ref cache; live)
	{
		if (cache.channel == id)
		{
			if (Clock.currTime(UTC()) - cache.check > 5.minutes)
			{
				hadPrevious = true;
				wasLive = cache.live;
				live[i] = live[$ - 1];
				live.length--;
				break;
			}
			else
				return cache.live;
		}
	}
	auto res = TwitchAPI.request("streams/" ~ id.to!string);
	bool isLive = res["stream"].type != Json.Type.null_;
	if (hadPrevious)
	{
		if (isLive != wasLive)
		{
			foreach (ev; liveChanged)
			{
				try
				{
					ev(channel, isLive);
				}
				catch (Exception e)
				{
					logError("Error in live change handler: %s", e);
				}
			}
		}
	}
	live ~= LiveCache(isLive, id, Clock.currTime(UTC()));
	return isLive;
}

alias LiveChangeEvent = void delegate(string, bool);

LiveChangeEvent[] liveChanged;

private LiveCache[] live;
