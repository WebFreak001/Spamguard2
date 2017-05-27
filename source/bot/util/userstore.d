module bot.util.userstore;

import vibe.db.mongo.database;
import vibe.db.mongo.collection;
import vibe.data.bson;

import mongoschema;

struct GlobalUserStorage
{
	@mongoUnique string username;
	Bson info;

	mixin MongoSchema;

	static Bson get(string username, string namespace)
	{
		auto store = tryFindOne(["username" : username]);
		if (store.isNull)
			return Bson.emptyObject;
		if (!namespace)
			return store.info;
		if (store.info.type != Bson.Type.object)
			return Bson.emptyObject;
		auto ptr = namespace in store.info.get!(Bson[string]);
		if (!ptr)
			return Bson.emptyObject;
		return *ptr;
	}

	static void set(string username, string namespace, Bson info)
	{
		auto store = tryFindOne(["username" : username]);
		if (store.isNull)
			store = GlobalUserStorage(username, Bson.emptyObject);
		if (store.info.type != Bson.Type.object)
			store.info = Bson.emptyObject;
		if (namespace)
			store.info[namespace] = info;
		else
			store.info = info;
		store.save();
	}
}

private struct Target
{
	string username, channel;
}

struct ChannelUserStorage
{
	@mongoUnique Target identifier;
	Bson info;

	mixin MongoSchema;

	static Bson get(string username, string channel, string namespace)
	{
		if (channel.length > 0 && channel[0] == '#')
			channel = channel[1 .. $];
		auto store = tryFindOne(["identifier" : Target(username, channel)]);
		if (store.isNull)
			return Bson.emptyObject;
		if (!namespace)
			return store.info;
		if (store.info.type != Bson.Type.object)
			return Bson.emptyObject;
		auto ptr = namespace in store.info.get!(Bson[string]);
		if (!ptr)
			return Bson.emptyObject;
		return *ptr;
	}

	static void set(string username, string channel, string namespace, Bson info)
	{
		if (channel.length > 0 && channel[0] == '#')
			channel = channel[1 .. $];
		auto store = tryFindOne(["identifier" : Target(username, channel)]);
		if (store.isNull)
			store = ChannelUserStorage(Target(username, channel), Bson.emptyObject);
		if (store.info.type != Bson.Type.object)
			store.info = Bson.emptyObject;
		if (namespace)
			store.info[namespace] = info;
		else
			store.info = info;
		store.save();
	}
}

void setupUserStore(MongoDatabase db)
{
	db["global_user_store"].register!GlobalUserStorage;
	db["channel_user_store"].register!ChannelUserStorage;
}

long longPropertyFor(string property)(string viewer, string streamer, long diff = 0)
{
	auto obj = ChannelUserStorage.get(viewer, streamer, "properties");
	auto value = obj.tryIndex(property);
	if (value.isNull)
		value = Bson(0L);
	if (diff != 0)
	{
		value = Bson(value.get.get!long + diff);
		obj[property] = value.get;
		ChannelUserStorage.set(viewer, streamer, "properties", obj);
	}
	return value.get.get!long;
}

alias pointsFor = longPropertyFor!"points";
alias watchTimeFor = longPropertyFor!"watchTime";
