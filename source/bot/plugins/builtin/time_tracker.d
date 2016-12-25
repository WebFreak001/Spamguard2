module bot.plugins.builtin.time_tracker;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;
import bot.util.userstore;

import vibe.core.core;
import vibe.core.log;

import core.time;
import std.string;
import std.conv;

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

class TimeTrackerPlugin : IPlugin
{
	this(string websiteBase, string ignoreUser)
	{
		this.websiteBase = websiteBase;
		auto router = new CommandRouter();
		router.on("!points", &getPoints);
		use(router);

		runTask({
			int minute = 0;
			while (true)
			{
				sleep(1.minutes);
				minute++;
				bool givePoints = false;
				if (minute >= 10)
				{
					minute = 0;
					givePoints = true;
				}
				foreach (user, multiplier; multipliers)
				{
					if (user[1].toLower == ignoreUser.toLower)
						continue;
					if (multiplier > 0 && givePoints)
						user[1].pointsFor(user[0], +multiplier);
					user[1].watchTimeFor(user[0], +1);
				}
			}
		});
	}

	Abort getPoints(IBot bot, string channel, scope Command command)
	{
		/*bot.send(command.raw.sender, "Your points in channel #" ~ channel ~ " are " ~ command.raw.sender.pointsFor(channel)
				.to!string ~ " as a result from watching for " ~ command.raw.sender.watchTimeFor(channel)
				.formatWatchTime);*/
		bot.send(channel,
				"View the current watchtime & points on " ~ websiteBase ~ channel[1 .. $] ~ "/points");
		return Abort.yes;
	}

	override Abort onMessage(IBot bot, CommonMessage msg)
	{
		string channel = msg.target[1 .. $];
		logInfo("Target: %s, sender: %s", channel, msg.sender);
		multipliers[[channel, msg.sender]] = 2;
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username)
	{
		logInfo("Channel: %s, join: %s", channel, username);
		multipliers[[channel, username]] = 1;
	}

	override void onUserLeave(IBot, string channel, string username)
	{
		logInfo("Channel: %s, part: %s", channel, username);
		multipliers.remove([channel, username]);
	}

private:
	string websiteBase;
	int[string[2]] multipliers;
}
