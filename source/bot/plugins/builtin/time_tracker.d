module bot.plugins.builtin.time_tracker;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;
import bot.util.userstore;
import bot.twitch.stream;

import vibe.vibe;

import core.time;
import std.string;
import std.conv;
import std.math;
import std.typecons;

string digit2(string n)
{
	return n.length < 2 ? '0' ~ n : n;
}

string formatWatchTime(long time)
{
	auto hours = time / 60;
	auto minutes = time % 60;
	return hours.to!string ~ "h" ~ minutes.to!string.digit2 ~ "m";
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
		router.on("!import :url", &importPoints);
		use(router);

		liveChanged ~= &onLiveChange;

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
					if (!included.canFind(multiplier.channel))
						included ~= multiplier.channel.toLower[1 .. $];
					if (!multiplier.channel.isLive || multiplier.username.toLower == ignoreUser.toLower)
						continue;
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

	string[] included;
	void onLiveChange(string channel, bool live)
	{
		if (bot && included.canFind(channel.toLower))
			bot.send('#' ~ channel, live ? "Channel is now live, tracking points"
					: "Channel no longer live, stopped tracking points.");
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

	Abort importPoints(IBot bot, string channel, scope Command command)
	{
		if (command.raw.senderRank < Rank.mod)
		{
			return Abort.no;
		}
		string url = command.params["url"];
		if (url == "confirm")
		{
			if (lastURL.length < 5 || lastURL[0 .. 4] != "http")
			{
				bot.send(channel, "Use `!import <url>` first");
			}
			else
			{
				try
				{
					string ret;
					requestHTTP(lastURL, (scope req) {  }, (scope res) {
						if (res.statusCode == 200)
							ret = res.bodyReader.readAllUTF8(false, 1024 * 1024 * 40);
					});
					if (!ret.length)
					{
						bot.send(channel, "Could not download points.");
						return Abort.yes;
					}
					import std.csv : csvReader;

					try
					{
						auto reader = ret.csvReader!(Tuple!(string, long, long,
								long))(["Username", "Twitch User ID", "Current Points", "All Time Points"]);
						foreach (entry; reader)
						{
							import bot.twitch.userids;

							entry[1].overridePointsFor(channel, entry[2]);
							entry[1].overrideWatchTimeFor(channel, entry[3]);
							updateUser(entry[0], entry[1]);
						}
						bot.send(channel, "Successfully imported data.");
					}
					catch (Exception e)
					{
						logError("Invalid data format: %s", e);
						bot.send(channel, "Data not in valid format. Can only import revlobot points.");
					}
				}
				catch (Exception e)
				{
					logError("Download error: %s", e);
					bot.send(channel, "Could not download points. Error during download.");
				}
			}
		}
		else
		{
			lastURL = url;
			if (url != "cancel")
				bot.send(channel,
						"This is about to replace the current leaderboards. Type `!import confirm` to confirm");
		}
		return Abort.yes;
	}

	string lastURL;

	override Abort onMessage(IBot bot, CommonMessage msg)
	{
		if (rewardActive)
		{
			string channel = msg.target[1 .. $];
			put(channel, msg.sender, msg.senderID, 2);
		}
		return Abort.no;
	}

	override void onUserJoin(IBot bot, string channel, string username)
	{
		import bot.twitch.userids : useridFor;

		put(channel, username, useridFor(username), 1);
		this.bot = bot;
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
	IBot bot;
}

struct ChannelMultiplier
{
	string channel;
	long userID;
	string username;
	int multiplier;
}
