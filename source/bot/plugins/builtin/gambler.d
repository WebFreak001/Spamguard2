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
import std.math : abs;

class GamblerPlugin : IPlugin {
	this() {
		auto router = new CommandRouter();
		router.on("!gamble :amount", &gamble, "rand(0, 100) where, 100 is 10x, 90..99 = 4x, 66..89 = 2x, else lose");
		router.on("!g :amount", &gamble);
		router.on("!flip :amount", &flip, "rand(0, 1) where 0 = lose, 1 = 2x");
		router.on("!f :amount", &flip);
		router.on("!roulette :amount", &roulette, "bet will be multipled by one of these: 0, 0.5, 1, 1.5, 2");
		router.on("!r :amount", &roulette);
		router.on("!kill :user :amount", &kill,
				"rand(0, max(0, 100 - $amount / 1000)) where 0 is kill successfull (target dies), else target gets $amount");
		router.on("!k :user :amount", &kill);
		use(router);
	}

	Abort gamble(IBot bot, string channel, scope Command command) {
		long amount = 0;
		try {
			amount = command.params["amount"].to!long;
		} catch (ConvException) {
			amount = 0;
		}
		if (amount <= 0)
			bot.send(channel,
					"@" ~ command.raw.sender
					~ " use `!gamble x`, where x is a positive non-zero integer to gamble x points. (You need to own at least x points)");
		else {
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel, "@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else {
				int roll = uniform!"[]"(1, 100);

				switch (roll) {
				case 100:
					amount *= 9;
					break;
				case 90: .. case 99:
					amount *= 3;
					break;
				case 66: .. case 89:
					amount *= 1;
					break;
				default:
					amount = -amount;
					break;
				}

				import std.format : format;

				auto newAmount = command.raw.senderID.pointsFor(channel, amount);
				bot.send(channel, format("@%s rolled %d, %s %d points. Has %d points now!", command.raw.sender, roll,
						amount > 0 ? "won" : "lost", amount.abs, newAmount));
			}
		}
		return Abort.yes;
	}

	Abort flip(IBot bot, string channel, scope Command command) {
		long amount = 0;
		try {
			amount = command.params["amount"].to!long;
		} catch (ConvException) {
			amount = 0;
		}
		if (amount <= 0)
			bot.send(channel,
					"@" ~ command.raw.sender
					~ " use `!flip x`, where x is a positive non-zero integer to gamble x points. (You need to own at least x points)");
		else {
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel, "@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else {
				if (uniform(0, 2))
					amount = -amount;

				import std.format : format;

				auto newAmount = command.raw.senderID.pointsFor(channel, amount);
				bot.send(channel, format("@%s got %s, %s %d points. Has %d points now!", command.raw.sender, amount > 0
						? "heads" : "tails", amount > 0 ? "won" : "lost", amount.abs, newAmount));
			}
		}
		return Abort.yes;
	}

	Abort roulette(IBot bot, string channel, scope Command command) {
		long amount = 0;
		try {
			amount = command.params["amount"].to!long;
		} catch (ConvException) {
			amount = 0;
		}
		if (amount <= 0)
			bot.send(channel,
					"@" ~ command.raw.sender
					~ " use `!roulette x`, where x is a positive non-zero integer to gamble x points. (You need to own at least x points)");
		else {
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel, "@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else {
				float[] mul = [0, 0.5, 1, 1.5, 2];
				size_t val = uniform(0, mul.length);
				amount = cast(long)(amount * mul[val]) - amount;
				import std.format : format;

				auto newAmount = command.raw.senderID.pointsFor(channel, amount);
				bot.send(channel, format("@%s %s %d points. Has %d points now!", command.raw.sender, amount > 0 ? "won"
						: "lost", amount.abs, newAmount));
			}
		}
		return Abort.yes;
	}

	Abort kill(IBot bot, string channel, scope Command command) {
		long amount = 0;
		try {
			amount = command.params["amount"].to!long;
		} catch (ConvException) {
			amount = 0;
		}
		string toUser = command.params["user"];
		if (amount <= 0 || !toUser)
			bot.send(channel, "@" ~ command.raw.sender
					~ " use `!kill user x`, where x is a positive non-zero integer to gamble x points. (You need to own at least x points), foreach 1000p = 1%");
		else {
			if (toUser[0] == '@')
				toUser = toUser[1 .. $];
			long current = command.raw.senderID.pointsFor(channel);
			if (amount > current)
				bot.send(channel, "@" ~ command.raw.sender ~ " you don't have the required amount of points.");
			else {

				long toUserID;
				try {
					import bot.twitch.userids : useridFor;

					toUserID = useridFor(toUser);
				} catch (Exception e) {
					bot.send(channel, "@" ~ command.raw.sender ~ ", Could not find '" ~ toUser ~ "'");
					return Abort.yes;
				}

				import std.algorithm : max;

				auto val = uniform!"[]"(0.0f, 100.0f);
				auto newAmount = command.raw.senderID.pointsFor(channel, -amount);
				if (val <= amount / 1000.0f) {
					toUserID.pointsFor(channel, -toUserID.pointsFor(channel));
					bot.send(channel, format("@%s killed @%s!", command.raw.sender, toUser));
				} else {
					toUserID.pointsFor(channel, amount);
					bot.send(channel, format("@%s failed to kill @%s, target gained %d points. Has %d points left!",
							command.raw.sender, toUser, amount, newAmount));
				}
			}
		}
		return Abort.yes;
	}

	override Abort onMessage(IBot bot, CommonMessage msg) {
		return Abort.no;
	}

	override void onUserJoin(IBot, string channel, string username) {
	}

	override void onUserLeave(IBot, string channel, string username) {
	}
}
