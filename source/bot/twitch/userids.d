module bot.twitch.userids;

import vibe.data.json;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import bot.twitch.api;

import mongoschema;

import std.conv;
import std.datetime;
import std.string;

struct UserIDCache
{
	@mongoUnique long userID;
	string username;
	SchemaDate requestDate = SchemaDate.now;

	mixin MongoSchema;

	static UserIDCache fromUser(Json user)
	{
		// { _id: string, name: string }
		auto id = user["_id"].get!string.to!long;
		auto name = user["name"].get!string.toLower;
		return UserIDCache(id, name, SchemaDate.now);
	}
}

string usernameFor(long userID)
{
	auto existing = UserIDCache.tryFindOne(["userID" : userID]);
	if (!existing.isNull && Clock.currTime(UTC()) - existing.requestDate.toSysTime <= 7.days)
		return existing.username;
	auto user = TwitchAPI.request("users/" ~ userID.to!string);
	auto c = UserIDCache.fromUser(user);
	if (!existing.isNull)
		c.bsonID = existing.bsonID;
	c.requestDate = SchemaDate.now;
	c.save();
	return c.username;
}

long useridFor(string username)
{
	auto existing = UserIDCache.tryFindOne(["username" : username]);
	if (!existing.isNull && Clock.currTime(UTC()) - existing.requestDate.toSysTime <= 7.days)
		return existing.userID;
	auto user = TwitchAPI.request("users", "login=" ~ username.toLower);
	auto r = UserIDCache.fromUser(user["users"][0]);
	auto res = UserIDCache.tryFindOne(["userID" : r.userID]);
	if (!res.isNull)
		r.bsonID = res.bsonID;
	r.requestDate = SchemaDate.now;
	r.save();
	return r.userID;
}

void updateUser(string username, long userID)
{
	auto existing = UserIDCache.tryFindOne(["userID" : userID]);
	if (existing.isNull)
	{
		UserIDCache(userID, username, SchemaDate.now).save();
	}
	else
	{
		existing.username = username.toLower;
		existing.requestDate = SchemaDate.now;
		existing.save();
	}
}
