module bot.plugins.builtin.time_tracker;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;
import bot.util.userstore;
import bot.twitch.stream;

import vibe.core.core;

import core.time;
import std.string;
import std.conv;
import std.math;

string digit2(string n)
{
	return n.length < 2 ? '0' ~ n : n;
}

string formatWatchTime(long time)
{
	auto hours = time / 60;
	auto minutes = time % 60;
	return hours.to!string ~ ":" ~ minutes.to!string.digit2;
}

string compactWatchTime(long time)
{
	if (time < 100)
		return time.to!string ~ "m";
	else
		return (round(time / 6.0) / 10.0).to!string ~ "h";
}

class TimeTrackerPlugin : IPlugin
{
	this(string websiteBase, string ignoreUser, bool rewardActive, int minutesPerPoint = 10)
	{
		this.websiteBase = websiteBase;
		this.rewardActive = rewardActive;
		auto router = new CommandRouter();
		router.on("!points", &getPoints);
		router.on("!leaderboard", &getAllPoints);
		use(router);

		runTask({
			int minute = 0;
			while (true)
			{
				sleep(1.minutes);
				minute++;
				bool givePoints = false;
				if (minute >= minutesPerPoint)
				{
					minute = 0;
					givePoints = true;
				}
				foreach (ref multiplier; multipliers)
				{
					if (!multiplier.channel.isLive)
					{
						continue;
					}
					if (multiplier.multiplier > 0 && givePoints)
					{
						multiplier.userID.pointsFor(multiplier.channel, +multiplier.multiplier);
						multiplier.multiplier = 1;
					}
					multiplier.userID.watchTimeFor(multiplier.channel, +1);
				}
			}
		});
	}

	Abort getPoints(IBot bot, string channel, scope Command command)
	{
		bot.send(channel, "@" ~ command.raw.sender ~ " points: " ~ command.raw.senderID.pointsFor(channel)
				.to!string ~ " (watched for " ~ command.raw.senderID.watchTimeFor(channel)
				.compactWatchTime ~ ")");
		return Abort.yes;
	}

	Abort getAllPoints(IBot bot, string channel, scope Command command)
	{
		bot.send(channel, "View the current leaderboard on " ~ websiteBase ~ channel[1 .. $] ~ "/points");
		return Abort.yes;
	}

	override Abort onMessage(IBot bot, CommonMessage msg)
	{
		if (rewardActive)
		{
			string channel = msg.target[1 .. $];
			put(channel, msg.sender, msg.senderID, 2);
		}
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username)
	{
		import bot.twitch.userids;

		put(channel, username, useridFor(username), 1);
	}

	override void onUserLeave(IBot, string channel, string username)
	{
		foreach_reverse (i, multiplier; multipliers)
		{
			if (multiplier.username == username)
			{
				if (!channel.length || multiplier.channel == channel)
				{
					multipliers[i] = multipliers[$ - 1];
					multipliers.length--;
				}
			}
		}
	}

	void put(string channel, string username, long userID, int newMultiplier)
	{
		bool found;
		foreach (ref multiplier; multipliers)
		{
			if (multiplier.channel == channel && multiplier.userID == userID)
			{
				found = true;
				multiplier.username = username;
				multiplier.multiplier = newMultiplier;
				break;
			}
		}
		if (!found)
			multipliers ~= ChannelMultiplier(channel, userID, username, newMultiplier);
	}

private:
	bool rewardActive;
	string websiteBase;
	ChannelMultiplier[] multipliers;
}

struct ChannelMultiplier
{
	string channel;
	long userID;
	string username;
	int multiplier;
}
