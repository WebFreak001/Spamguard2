module bot.plugins.midware.router;

import bot.plugins.manager;

import std.algorithm;
import std.exception;
import std.string;
import std.regex;
import std.conv;
import std.uni;

struct Command
{
    CommonMessage raw;
    string[string] flags;
    string[string] params;
}

private struct CommandPattern
{
    string base;
    ushort[] paramLocs;
}

private string[] match(string msg, CommandPattern pattern)
{
    ushort pos = 0;
    ushort curParam = 0;
    string[] params = [""];
    bool inString = false;
    bool escape = false;
    bool lastWhite = true;
    foreach (c; msg)
    {
        if (c.isWhite && lastWhite && !inString)
        {
            continue;
        }
        lastWhite = c.isWhite;
        if (curParam < pattern.paramLocs.length && pos == pattern.paramLocs[curParam])
        {
            if (c == '"' && !inString)
            {
                if (pos < pattern.base.length && params[$ - 1].length)
                    return null;
                if (params[$ - 1].length)
                    params[$ - 1].length--;
                inString = true;
            }
            else
            {
                if (inString && !escape && c == '"')
                {
                    inString = false;
                    if (pos < pattern.base.length)
                    {
                        pos++;
                        curParam++;
                        params ~= "";
                    }
                }
                else if (escape && c == '"')
                {
                    params[$ - 1] ~= '"';
                    escape = false;
                }
                else if (escape && c == 'n')
                {
                    params[$ - 1] ~= '\n';
                    escape = false;
                }
                else if (inString && c == '\\')
                {
                    if (escape)
                    {
                        params[$ - 1] ~= '"';
                        escape = false;
                    }
                    else
                        escape = true;
                }
                else if (pos < pattern.base.length && c == pattern.base[pos] && !inString)
                {
                    escape = false;
                    pos++;
                    curParam++;
                    params ~= "";
                }
                else
                {
                    escape = false;
                    params[$ - 1] ~= c;
                }
            }
        }
        else
        {
            if (pos >= pattern.base.length)
                return null;
            if (c == pattern.base[pos])
                pos++;
            else
            {
                if (!c.isWhite)
                    return null;
            }
        }
    }
    if (pos < pattern.base.length)
        return null;
    if (curParam < pattern.paramLocs.length && pos == pattern.paramLocs[curParam])
        params ~= "";
    return params[0 .. $ - 1];
}

version (unittest) void assertEq(T, U)(T t, U u)
{
    string a = t.to!string;
    if (t is null)
        a = "null";
    string b = u.to!string;
    if (u is null)
        b = "null";
    assert(t == u, a ~ " and " ~ b ~ " are not equal!");
}

version (unittest) void assertEqRnd(T)(T[] t, T[] u)
{
    string a = t.to!string;
    if (t is null)
        a = "null";
    string b = u.to!string;
    if (u is null)
        b = "null";
    assert(!((a is null) ^ (b is null)), a ~ " and " ~ b ~ " are not equal!");
    foreach_reverse (elem; t)
        if (!u.canFind(elem))
            assert(0, a ~ " and " ~ b ~ " are not randomly equal!");
    foreach_reverse (elem; u)
        if (!t.canFind(elem))
            assert(0, a ~ " and " ~ b ~ " are not randomly equal!");
}

unittest
{
    assertEq(match("!test", CommandPattern("!test", [])), []);
    assert(!match("!testg", CommandPattern("!test", [])));
    assertEq(match("!test gioejihot", CommandPattern("!test ", [6])), ["gioejihot"]);
    assertEq(match("!test \"abc def\\\"  geh\"", CommandPattern("!test ", [6])), ["abc def\"  geh"]);
    assertEq(match("!test abc def geh", CommandPattern("!test   ", [6, 7, 8])),
            ["abc", "def", "geh"]);
    assertEq(match("!test abc def geh f", CommandPattern("!test   ", [6, 7,
            8])), ["abc", "def", "geh f"]);
    assertEq(match("!editcom  !foo append wegh",
            CommandPattern("!editcom  append ", [9, 17])), ["!foo", "wegh"]);
    assert(!match("!test", CommandPattern("!test foo", [])));
    assert(!match("!test", CommandPattern("!test  me", [6])));
    assertEq(match("!test foo me", CommandPattern("!test  me", [6])), ["foo"]);
}

alias CommandCallback = Abort delegate(IBot, string channel, scope Command commandInfo);

private enum Whitespaces = ctRegex!`\s+`;
private enum WordStart = ctRegex!`^\w+`;

struct PatternCallback
{
    this(string format, CommandCallback callback, string description)
    {
        this.description = description;
        this.rawFormat = format;
        format = format.strip.replaceAll(Whitespaces, " ");
        this.callback = callback;

        int unnamedCounter = 0;
        bool escape = false;
        while (format.length)
        {
            immutable c = format[0];
            if (c == '\\')
            {
                escape = true;
            }
            else
            {
                if (escape)
                {
                    if (c == ':')
                    {
                        pattern.base ~= ':';
                        escape = false;
                        format = format[1 .. $];
                        continue;
                    }
                    else if (c == '*')
                    {
                        pattern.base ~= '*';
                        escape = false;
                        format = format[1 .. $];
                        continue;
                    }
                    else
                        pattern.base ~= '\\';
                    escape = false;
                }
                if (c == ':')
                {
                    pattern.paramLocs ~= cast(ushort) pattern.base.length;
                    format = format[1 .. $];
                    auto match = format.matchFirst(WordStart);
                    enforce(match && match.front,
                            "invalid parameter name start: '" ~ match.front ~ "'");
                    paramMap ~= match.front;
                    format = format[match.front.length .. $];
                    continue;
                }
                else if (c == '*')
                {
                    pattern.paramLocs ~= cast(ushort) pattern.base.length;
                    paramMap ~= "_unnamed" ~ (++unnamedCounter).to!string;
                }
                else
                {
                    pattern.base ~= c;
                }
            }
            format = format[1 .. $];
        }

        string[] added;
        foreach (param; paramMap)
        {
            enforce(!added.canFind(param), "Duplicate parameter name '" ~ param ~ "'");
            added ~= param;
        }
    }

    CommandPattern pattern;
    CommandCallback callback;
    string[] paramMap;
    string rawFormat;
    string description;
}

string[string] extractFlags(ref string message)
{
    string[string] flags;
    string fixed = "";
    bool inString = false;
    bool escape = false;
    bool flag = false;
    bool doubleFlag = false;
    bool doubleFlagValue = false;
    string flagName = "";
    foreach (c; message)
    {
        if (escape)
            escape = false;
        else
        {
            if (c == '\\' && inString)
                escape = true;
            if (c == '"')
                inString = !inString;
        }

        if (inString)
            fixed ~= c;
        else
        {
            if (c == '-')
            {
                if (!flag)
                    flag = true;
                else if (!doubleFlag)
                {
                    flagName = "";
                    doubleFlagValue = false;
                    doubleFlag = true;
                }
            }
            else if (c.isWhite && doubleFlag && doubleFlagValue)
            {
                if (flagName !in flags)
                    flags[flagName] = "";
                flags[flagName] ~= '\0';
                flag = doubleFlag = doubleFlagValue = false;
                fixed ~= c;
            }
            else if ((c.isWhite || c == '=') && doubleFlag && !doubleFlagValue)
            {
                if (flagName.length)
                    doubleFlagValue = true;
                else
                {
                    flag = doubleFlag = doubleFlagValue = false;
                    fixed ~= c;
                }
            }
            else if (c.isWhite && flag)
            {
                flag = false;
                fixed ~= c;
            }
            else
            {
                if (doubleFlag)
                {
                    if (!doubleFlagValue)
                    {
                        flagName ~= c;
                    }
                    else
                    {
                        if (flagName !in flags)
                            flags[flagName] = "";
                        flags[flagName] ~= c;
                    }
                }
                else if (flag)
                {
                    string boolFlagName = [c];
                    if (boolFlagName !in flags)
                        flags[boolFlagName] = "";
                }
                else
                    fixed ~= c;
            }
        }
    }
    message = fixed;
    foreach (key, ref value; flags)
        if (value.length && value[$ - 1] == '\0')
            value.length--;
    return flags;
}

unittest
{
    string[string] flags;
    string cmd = "!foo -abc --foo=bar bob --hello world";
    flags = cmd.extractFlags;
    assertEqRnd(flags.keys, ["a", "b", "c", "foo", "hello"]);
    assertEq(cmd, "!foo   bob ");
    assert("a" in flags);
    assert("b" in flags);
    assert("c" in flags);
    assertEq(flags["foo"], "bar");
    assertEq(flags["hello"], "world");

    cmd = "!convert --file a.txt --file b.txt --file c.txt --out=docx fast";
    flags = cmd.extractFlags;
    assertEqRnd(flags.keys, ["file", "out"]);
    assertEq(cmd, "!convert     fast");
    assertEq(flags["file"], "a.txt\0b.txt\0c.txt");
    assertEq(flags["out"], "docx");
}

class CommandRouter : PluginMidware
{
    // !to :user :duration
    // !to -s Bob
    CommandRouter on(string format, CommandCallback callback, string description = null)
    {
        patterns ~= PatternCallback(format, callback, description);
        return this;
    }

    Abort handleMessage(IPlugin, IBot bot, ref CommonMessage msg)
    {
        string text = msg.message.idup;
        auto flags = text.extractFlags;
        foreach (pattern; patterns)
        {
            auto match = text.match(pattern.pattern);
            if (!match)
                continue;
            Command command;
            command.flags = flags;
            foreach (i, part; match)
                command.params[pattern.paramMap[i]] = part;
            command.raw = msg;
            auto abort = pattern.callback(bot, msg.target, command);
            if (abort)
                return Abort.yes;
        }
        return Abort.no;
    }

private:
    public PatternCallback[] patterns;
}
