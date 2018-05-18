module bot.plugins.manager;

public import bot.ibot;
public import bot.types;

import vibe.core.log;

enum Abort : bool
{
	no = false,
	yes
}

interface PluginMidware
{
	Abort handleMessage(IPlugin, IBot, ref CommonMessage);
}

abstract class IPlugin
{
protected:
	void use(PluginMidware midware)
	{
		midwares ~= midware;
	}

	void onActive(IBot, CommonMessage)
	{
	}

	abstract Abort onMessage(IBot, CommonMessage);
	abstract void onUserJoin(IBot, string channel, string username);
	abstract void onUserLeave(IBot, string channel, string username);

private:
	Abort handleMessage(IBot bot, CommonMessage message)
	{
		logDebug("Got message %s", message);
		foreach (midware; midwares)
			if (midware.handleMessage(this, bot, message) == Abort.yes)
				return Abort.yes;
		return onMessage(bot, message);
	}

	void handleUserJoin(IBot bot, string channel, string username)
	{
		onUserJoin(bot, channel, username);
	}

	void handleUserLeave(IBot bot, string channel, string username)
	{
		onUserLeave(bot, channel, username);
	}

	public PluginMidware[] midwares;
}

class PluginManager
{
	this()
	{
	}

	void bind(IBot bot)
	{
		bots ~= bot;
		bot.addOnJoin(&onJoin);
		bot.addOnLeave(&onLeave);
		bot.addOnMessage(&onMessage);
	}

	void add(IPlugin plugin)
	{
		plugins ~= plugin;
	}

	void onJoin(IBot bot, string channel, string username)
	{
		foreach (plugin; plugins)
		{
			try
			{
				plugin.handleUserJoin(bot, channel, username);
			}
			catch (Exception e)
			{
				logError("Error in plugin: %s", e);
			}
		}
	}

	void onLeave(IBot bot, string channel, string username)
	{
		foreach (plugin; plugins)
		{
			try
			{
				plugin.handleUserLeave(bot, channel, username);
			}
			catch (Exception e)
			{
				logError("Error in plugin: %s", e);
			}
		}
	}

	void onMessage(IBot bot, CommonMessage msg)
	{
		foreach (plugin; plugins)
			plugin.onActive(bot, msg);

		foreach (plugin; plugins)
		{
			try
			{
				if (plugin.handleMessage(bot, msg))
					return;
			}
			catch (Exception e)
			{
				logError("Error in plugin: %s", e);
			}
		}
	}

private:
	IBot[] bots;
	public IPlugin[] plugins;
}
