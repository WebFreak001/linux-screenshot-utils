import std.algorithm;
import std.bitmanip;
import std.string;
import std.stdio;

import gtk.Main;

import region;
import selection;

import gtk.Main;
import gdk.Pixbuf;

class NotImplementedException : Exception
{
	public this(string msg = "Not implemented yet!", string file = __FILE__,
			size_t line = __LINE__, Throwable next = null)
	{
		super(msg, file, line, next);
	}
}

int main(string[] args)
{
	if (args[0].endsWith("-region", "-objects", "-fullscreen", "-window"))
		args = [args[0], args[0]] ~ args[1 .. $];

	if (args.length < 3)
	{
		stderr.writeln("Usage: ", args[0],
				" [version/region/objects/fullscreen/window] ([jpeg/png/tiff/ico/bmp])");
		return 1;
	}

	string mode = args[1].toLower;
	string type = args[2];

	Region[] regions;
	Pixbuf image;
	bool success = true;
	SelectionEvent handleSelection = (img, reg) { image = img; regions = reg; };
	if (mode.endsWith("version"))
	{
		stdout.rawWrite(nativeToBigEndian!int(1));
		return 0;
	}
	else if (mode.endsWith("region"))
	{
		Main.init(args);
		auto sel = new Selection(false);
		sel.onSelected = handleSelection;
		Main.run();
		success = sel.success;
	}
	else if (mode.endsWith("objects"))
	{
		Main.init(args);
		auto sel = new Selection(true);
		sel.onSelected = handleSelection;
		Main.run();
		success = sel.success;
	}
	else if (mode.endsWith("fullscreen"))
	{
		Main.init(args);
		image = captureAll();
	}
	// else if (mode.endsWith("window"))
	// {
	// }
	else
	{
		throw new NotImplementedException();
	}

	if (!success)
		return 1;

	if (regions.length == 1)
	{
		image = image.newSubpixbuf(regions[0].x, regions[0].y, regions[0].w, regions[0].h);
	}
	else if (regions.length > 1)
	{
		int minX = regions[0].x;
		int minY = regions[0].y;
		int maxX = regions[0].x + regions[0].w;
		int maxY = regions[0].y + regions[0].h;

		foreach (region; regions[1 .. $])
		{
			minX = min(minX, region.x);
			minY = min(minY, region.y);
			maxX = max(maxX, region.x + region.w);
			maxY = max(maxY, region.y + region.h);
		}

		auto src = image;
		image = new Pixbuf(src.getColorspace(), true, src.getBitsPerSample(), maxX - minX, maxY - minY);
		image.fill(0);

		foreach (region; regions)
			src.copyArea(region.x, region.y, region.w, region.h, image, region.x - minX, region.y - minY);
	}

	version (Posix)
	{
		import core.sys.posix.unistd : isatty;

		if (isatty(stdout.fileno))
		{
			stderr.writeln("Not outputting image to console because it is a TTY.");
			return 1;
		}
	}

	image.saveToCallbackv(&pixbufSaveCallback, null, type, null, null);

	return 0;
}

extern (C) int pixbufSaveCallback(char* buf, size_t count, GError** error, void* data)
{
	auto dat = (cast(ubyte*) buf)[0 .. count];
	stdout.rawWrite(dat);
	return 1;
}
