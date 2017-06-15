module bot.twitch.stream;

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
	foreach_reverse (i, ref cache; live)
	{
		if (cache.channel == id)
		{
			if (Clock.currTime(UTC()) - cache.check > 20.minutes)
			{
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
	live ~= LiveCache(isLive, id, Clock.currTime(UTC()));
	return isLive;
}

private LiveCache[] live;
