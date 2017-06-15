module bot.irc.bot;

import bot.ibot;
import bot.types;

import vibeirc;

import core.time;

import vibe.core.log;
import vibe.core.core;

import std.algorithm;
import std.datetime;
import std.string;
import std.conv;

class IRCBot : IBot
{
	this(string host, string nickname, string password = "", ushort port = 6667)
	{
		client = new IRCClient;
		client.nickname = nickname;
		client.onDisconnect = &onDisconnect;
		client.onLogin = &onLogin;
		client.onUserJoin = &onUserJoin;
		client.onUserPart = &onUserPart;
		client.onUserQuit = &onUserQuit;
		client.onUnknownCommand = &onUnknownCommand;
		client.onUnknownNumeric = &onUnknownNumeric;

		this.host = host;
		this.password = password;
		this.port = port;
	}

	void join(string[] channels...)
	{
		if (connected)
		{
			foreach (channel; channels)
				joinImpl(channel);
		}
		else
		{
			channelQueue ~= channels;
			connect();
		}
	}

	string nickname() @property
	{
		return client.nickname;
	}

	void kick(string channel, string user, Duration duration)
	{
		client.send(channel, ".timeout " ~ user ~ " " ~ (cast(int) duration.total!"seconds").to!string);
	}

	void ban(string channel, string user)
	{
		client.send(channel, ".ban " ~ user);
	}

	void unban(string channel, string user)
	{
		client.send(channel, ".unban " ~ user);
	}

	void send(CommonMessage message)
	{
		if (Clock.currTime - lastMessage < 1.seconds)
		{
			if (sentFast)
				return;
			else
				sentFast = true;
		}
		else
			sentFast = false;
		lastMessage = Clock.currTime;
		client.send(message.target, message.message.replace("\n", " "));
	}

	bool sentFast;

	void addOnMessage(MessageHandler handler)
	{
		messageHandlers ~= handler;
	}

	void addOnJoin(UserHandler handler)
	{
		joinHandlers ~= handler;
	}

	void addOnLeave(UserHandler handler)
	{
		leaveHandlers ~= handler;
	}

private:
	void connect()
	{
		client.connect(host, port, password);
	}

	void onUnknownNumeric(string prefix, int id, string[] arguments)
	{
		if (id == 372)
		{
			client.sendLine("CAP REQ :twitch.tv/tags twitch.tv/commands");
			client.sendLine("CAP REQ :twitch.tv/membership");
			connected = true;
			foreach (channel; channelQueue)
				joinImpl(channel);
		}
		else
			logInfo("prefix: %s, id: %s, arguments: %s", prefix, cast(Numeric) id, arguments);
	}

	void onUnknownCommand(string prefix, string command, string[] arguments)
	{
		auto userTypeIdx = prefix.indexOf("user-type=");
		auto userIdIdx = prefix.indexOf("user-id=");
		if (userTypeIdx != -1)
		{
			if (arguments.length > 2)
			{
				if (arguments[0] == "PRIVMSG")
				{
					assert(command.canFind("!"), command);
					string username = command[1 .. command.indexOf("!")];
					if (username == nickname)
						return;
					string channel = arguments[1];
					string message = arguments[2 .. $].join(" ")[1 .. $];
					CommonMessage msg;
					msg.target = channel;
					msg.sender = username;
					if (userIdIdx != -1)
					{
						import bot.twitch.userids;

						auto semicolon = prefix.indexOf(";", userIdIdx);
						if (semicolon == -1)
							semicolon = prefix.length;
						msg.senderID = prefix[userIdIdx + "user-id=".length .. semicolon].to!long;
						updateUser(msg.sender, msg.senderID);
					}
					msg.message = message;
					Rank rank;
					if (username == channel[1 .. $])
						rank = Rank.admin;
					else
					{
						string typeStr = prefix[userTypeIdx + "user-type=".length .. $];
						auto semiColonIndex = typeStr.indexOf(';');
						if (semiColonIndex != -1)
							typeStr = typeStr[0 .. semiColonIndex];
						if (typeStr == "mod" || typeStr == "global_mod" || typeStr == "staff")
							rank = Rank.mod;
						else if (typeStr == "admin")
							rank = Rank.admin;
					}
					msg.senderRank = rank;
					foreach (handler; messageHandlers)
						handler(this, msg);
				}
			}
		}
		else
			logInfo("prefix: %s, command: %s, arguments: %s", prefix, command, arguments);
	}

	void onDisconnect(string reason)
	{
		connected = false;
		logInfo("Disconnected: %s", reason);
		sleep(10.seconds);
		logInfo("Attempting to reconnect");
		connect();
	}

	void joinImpl(string channel)
	{
		logInfo("Joining ", channel);
		client.join(channel);
	}

	void onLogin()
	{
		logInfo("Logged in");
	}

	void onUserJoin(User user, string channel)
	{
		foreach (handler; joinHandlers)
			handler(this, channel, user.nickname);
	}

	void onUserPart(User user, string channel, string reason)
	{
		foreach (handler; leaveHandlers)
			handler(this, channel, user.nickname);
	}

	void onUserQuit(User user, string reason)
	{
		foreach (handler; leaveHandlers)
			handler(this, "", user.nickname);
	}

	bool connected;
	string[] channelQueue;
	IRCClient client;
	string host, password;
	ushort port;
	MessageHandler[] messageHandlers;
	UserHandler[] joinHandlers, leaveHandlers;
	SysTime lastMessage;
}
