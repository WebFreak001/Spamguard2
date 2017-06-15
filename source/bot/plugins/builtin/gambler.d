module bot.plugins.builtin.gambler;

import bot.irc.bot;
import bot.plugins.manager;
import bot.plugins.midware.router;
import bot.util.userstore;

import vibe.core.core;
import vibe.core.log;

import core.time;
import std.string;
import std.conv;
import std.random;

class GamblerPlugin : IPlugin
{
	this()
	{
		auto router = new CommandRouter();
		router.on("!gamble :amount", &gamble);
		use(router);
	}

	Abort gamble(IBot bot, string channel, scope Command command)
	{
		long amount = 0;
		try
		{
			amount = command.params["amount"].to!long;
		}
		catch (ConvException)
		{
			amount = 0;
		}
		if (amount <= 0)
			bot.send(channel, "@" ~ command.raw.sender ~ " use `!gamble x`, where x is a positive non-zero integer to gamble x points. (You need to own at least x points)");
		else
		{
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel,
						"@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else
			{
				int roll = uniform!"[]"(1, 100);
				if (roll < 60)
				{
					auto newAmount = command.raw.senderID.pointsFor(channel, -amount);
					bot.send(channel, "@" ~ command.raw.sender ~ " rolled " ~ roll.to!string
							~ ", lost " ~ amount.to!string ~ " points. Has "
							~ newAmount.to!string ~ " points now.");
				}
				else if (roll == 100)
				{
					auto newAmount = command.raw.senderID.pointsFor(channel, +amount * 2);
					bot.send(channel, "@" ~ command.raw.sender ~ " rolled 100, won " ~ (amount * 2)
							.to!string ~ " points. Has " ~ newAmount.to!string ~ " points now.");
				}
				else
				{
					auto newAmount = command.raw.senderID.pointsFor(channel, +amount);
					bot.send(channel, "@" ~ command.raw.sender ~ " rolled " ~ roll.to!string
							~ ", won " ~ amount.to!string ~ " points. Has " ~ newAmount.to!string
							~ " points now.");
				}
			}
		}
		return Abort.yes;
	}

	override Abort onMessage(IBot bot, CommonMessage msg)
	{
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username)
	{
	}

	override void onUserLeave(IBot, string channel, string username)
	{
	}
}
