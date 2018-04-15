#!/usr/bin/env rdmd

import std.stdio;
import std.process;
import core.thread;
import std.datetime : seconds;
import std.string;

int main() {
	string openssl_version = executeShell(`grep "SHLIB_VERSION_NUMBER " /usr/include/openssl/opensslv.h | cut -d'"' -f2`).output.strip;

	string opensslArg;
	if (openssl_version == "1.1")
		opensslArg = "openssl-1.1";
	else if (openssl_version == "1.0.0")
		opensslArg = "openssl";
	else {
		stderr.writeln("Unknown openssl version '", openssl_version, "'!");
		return -1;
	}

	writeln("Sleeping");
	Thread.sleep(1.seconds);

	writeln("git pull");
	auto gp = pipeShell("git pull", Redirect());
	assert(!wait(gp.pid));

	writeln("dub build");
	auto dub = pipeShell("dub build --override-config=vibe-d:tls/" ~ opensslArg, Redirect());
	assert(!wait(dub.pid));

	writeln("killall");
	wait(pipeShell("killall -s SIGINT -w spamguard2", Redirect()).pid);

	writeln("launching screen");
	auto screen = pipeShell("screen -dm -S Spamguard ./spamguard2", Redirect());
	assert(!wait(screen.pid));

	return 0;
}
