module bot.plugins.builtin.twitch_highlight;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;

import std.exception;
import std.datetime;
import std.conv;

import vibe.core.log;
import vibe.data.json;
import vibe.http.client;

struct HighlightInfo
{
	Duration duration;
	string description;
	string submitter;
}

struct HighlightChannelInfo
{
	SysTime lastUpdate;
	HighlightInfo[] highlights;
	bool cleared = false;
}

string make2(long s)
{
	return s.to!string.make2;
}

string make2(string s)
{
	if (s.length == 0)
		return "00";
	if (s.length < 2)
		return "0" ~ s;
	return s;
}

class HighlightPlugin : IPlugin
{
	this(string websiteBase)
	{
		this.websiteBase = websiteBase;
		auto router = new CommandRouter();
		router.on("!highlight", &help);
		router.on("!highlight list", &highlightList);
		router.on("!highlight clear", &highlightClear);
		router.on("!highlight undo clear", &highlightUndo);
		router.on("!highlight :msg", &highlight);
		router.on("!help highlight", &help);
		use(router);
	}

	Abort highlightList(IBot bot, string channel, scope Command command)
	{
		auto twitchBot = enforce(cast(IRCBot) bot, "This is a twitch only command");
		bot.send(channel,
				"view all current highlights on " ~ websiteBase ~ channel[1 .. $] ~ "/highlights");
		return Abort.yes;
	}

	Abort highlightClear(IBot bot, string channel, scope Command command)
	{
		auto twitchBot = enforce(cast(IRCBot) bot, "This is a twitch only command");
		if (command.raw.senderRank < Rank.admin)
		{
			return Abort.yes;
		}
		auto info = channelVar(channel);
		info.lastUpdate = Clock.currTime;
		info.cleared = true;
		channelVar(channel) = info;
		bot.send(channel, "@" ~ command.raw.sender ~ ": cleared highlights");
		return Abort.yes;
	}

	Abort highlightUndo(IBot bot, string channel, scope Command command)
	{
		auto twitchBot = enforce(cast(IRCBot) bot, "This is a twitch only command");
		if (command.raw.senderRank < Rank.admin)
		{
			return Abort.yes;
		}
		auto info = channelVar(channel);
		info.lastUpdate = Clock.currTime;
		info.cleared = false;
		channelVar(channel) = info;
		bot.send(channel,
				"@" ~ command.raw.sender ~ ": reverted "
				~ info.highlights.length.to!string ~ " highlights");
		return Abort.yes;
	}

	Abort highlight(IBot bot, string channel, scope Command command)
	{
		auto twitchBot = enforce(cast(IRCBot) bot, "This is a twitch only command");
		SysTime now = Clock.currTime;
		auto info = channelVar(channel);
		if (now - info.lastUpdate < 10.seconds)
			return Abort.yes;
		if (now - info.lastUpdate < 5.minutes && command.raw.senderRank < Rank.mod)
		{
			bot.send(channel, "Please wait " ~ (now - info.lastUpdate)
					.to!string ~ " before highlighting again");
			return Abort.yes;
		}
		if (info.cleared)
		{
			info.highlights.length = 0;
			info.cleared = false;
		}
		requestHTTP("https://api.twitch.tv/kraken/streams/" ~ channel[1 .. $], (scope req) {
		}, (scope res) {
			Json data = res.readJson();
			if ("stream" !in data || data["stream"].type == Json.Type.null_)
			{
				bot.send(channel,
					"Why would you do this to me if the stream is offline? BibleThump");
			}
			else
			{
				SysTime startTime = SysTime.fromISOExtString(
					data["stream"]["created_at"].get!string);
				Duration dur = now - startTime;
				auto splits = dur.split!("hours", "minutes");
				info.highlights ~= HighlightInfo(dur, command.params["msg"], command.raw.sender);
				bot.send(channel, command.raw.sender ~ " has scheduled highlight at " ~ (
					splits.hours.to!string ~ ":" ~ splits.minutes.to!string.make2)
					~ " for addition. This is highlight #"
					~ info.highlights.length.to!string ~ " in this stream!");
			}
			info.lastUpdate = now;
			channelVar(channel) = info;
		});
		return Abort.yes;
	}

	Abort help(IBot bot, string channel, scope Command)
	{
		auto twitchBot = enforce(cast(IRCBot) bot, "This is a twitch only command");
		bot.send(channel, "!highlight - saves the current time in the twitch recording for later retrieval - Usage: !highlight (<msg>|list|clear|undo clear)");
		return Abort.yes;
	}

	override Abort onMessage(IBot, CommonMessage)
	{
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username)
	{
	}

	override void onUserLeave(IBot, string channel, string username)
	{
	}

	auto getChannelOrThrow(string channel)
	{
		auto ptr = channel in channelVars;
		if (ptr)
			return *ptr;
		throw new Exception("Channel not found");
	}

private:
	string websiteBase;

	ref auto channelVar(string channel) @property
	{
		auto ptr = channel in channelVars;
		if (ptr)
			return *ptr;
		return channelVars[channel] = (typeof(*ptr)).init;
	}

	HighlightChannelInfo[string] channelVars;
}
