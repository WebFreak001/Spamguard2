module bot.twitch.userids;

import vibe.data.json;

import bot.twitch.api;

import std.conv;
import std.datetime;
import std.string;

struct UserIDCache
{
	long userID;
	string username;
	SysTime requestDate;

	static UserIDCache fromUser(Json user)
	{
		// { _id: string, name: string }
		auto id = user["_id"].get!string.to!long;
		auto name = user["name"].get!string.toLower;
		return UserIDCache(id, name, Clock.currTime(UTC()));
	}
}

string usernameFor(long userID)
{
	foreach (i, ref c; cache)
	{
		if (c.userID == userID)
		{
			if (Clock.currTime(UTC()) - c.requestDate > 24.hours)
			{
				cache[i] = cache[$ - 1];
				cache.length--;
				break;
			}
			else
				return c.username;
		}
	}
	auto user = TwitchAPI.request("users/" ~ userID.to!string);
	auto c = UserIDCache.fromUser(user);
	cache ~= c;
	return c.username;
}

long useridFor(string username)
{
	foreach (i, ref c; cache)
	{
		if (c.username == username.toLower)
		{
			if (Clock.currTime(UTC()) - c.requestDate > 6.hours)
			{
				cache[i] = cache[$ - 1];
				cache.length--;
				break;
			}
			else
				return c.userID;
		}
	}
	auto user = TwitchAPI.request("users", "login=" ~ username.toLower);
	auto r = UserIDCache.fromUser(user["users"][0]);
	foreach_reverse (i, ref c; cache)
	{
		if (c.userID == r.userID)
		{
			c.username = r.username.toLower;
			c.requestDate = r.requestDate;
			return r.userID;
		}
	}
	cache ~= r;
	return r.userID;
}

void updateUser(string username, long userid)
{
	foreach_reverse (i, ref c; cache)
	{
		if (c.userID == userid)
		{
			c.username = username.toLower;
			c.requestDate = Clock.currTime(UTC());
			return;
		}
	}
	cache ~= UserIDCache(userid, username, Clock.currTime(UTC()));
}

private UserIDCache[] cache;
