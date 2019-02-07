import region;
import wmregions;

import cairo.Context;
import cairo.ImageSurface;
import cairo.Pattern;

import gtk.Clipboard;
import gtk.DrawingArea;
import gtk.Main;
import gtk.MainWindow;
import gtk.Widget;
import gtk.Window;

import gdk.Cairo;
import gdk.Device;
import gdk.Event;
import gdk.Pixbuf;
import gdk.Screen;
import gdk.Seat;
import gdk.Window : GdkWindow = Window;

import std.format;
import std.math;
import std.string;

import core.thread;

Pixbuf captureAll()
{
	auto root = GdkWindow.getDefaultRootWindow();
	auto width = root.getWidth();
	auto height = root.getHeight();
	return root.getFromWindow(0, 0, width, height);
}

class Selection : MainWindow
{
	SelectionWidget preview;

	this(bool objects)
	{
		super("Capture");

		auto pixbuf = captureAll();

		preview = new SelectionWidget(pixbuf, this, objects);
		add(preview);
		addOnButtonPress(&preview.onButtonPress);
		addOnKeyPress(&preview.onButtonPress);
		addOnButtonRelease(&preview.onButtonRelease);
		addOnKeyRelease(&preview.onButtonRelease);
		addOnMotionNotify(&preview.onMouseMove);
		addOnScroll(&preview.onScroll);
		showAll();

		initWindow(pixbuf.getWidth(), pixbuf.getHeight());
	}

	void initWindow(int width, int height)
	{
		version (Windows)
		{
			setGravity(GdkGravity.NORTH_WEST);
			move(0, 0);
			setDefaultSize(width, height);
			setSizeRequest(width, height);
		}
		else
		{
			GdkWindow gdkwin = getWindow();
			assert(gdkwin);
			gdkwin.setOverrideRedirect(true);
			gdkwin.moveResize(0, 0, width, height);
			gdkwin.show();
			gdkwin.setSkipPagerHint(true);
			gdkwin.setSkipTaskbarHint(true);

			Seat seat = gdkwin.getDisplay().getDefaultSeat();
			seat.grab(gdkwin, GdkSeatCapabilities.ALL, false, null, null, null, null);
			Screen screen;
			double x, y;
			seat.getPointer().getPositionDouble(screen, x, y);
			preview.moveMouse(x, y);
		}
	}

	@property ref auto onSelected()
	{
		return preview.onSelected;
	}

	@property ref auto success()
	{
		return preview.success;
	}
}

alias SelectionEvent = void delegate(Pixbuf, Region[]);

void fix(ref Region[] regions)
{
	foreach (ref region; regions)
	{
		region.fix();
	}
}

class SelectionWidget : DrawingArea
{
private:
	Pixbuf _img;
	Pattern _scaled;
	Window _window;
	bool _lmb;
	bool _fastCapture = false;
	Region[] _regions;
	size_t _selectedRegion;
	bool _move = false;
	Device _mouse;
	int _mx, _my;
	int _startX, _startY;
	int _time = 0;
	int _radius = 120;
	SelectionEvent _onSelected;
	Region[] _objects;
	bool stop = false;
	bool _success = false;
	uint _lastColor;
	string _colorString;

public:
	this(Pixbuf buf, Window window, bool objects)
	{
		super();
		_img = buf;
		_window = window;
		_mouse = getDisplay().getDeviceManager().getClientPointer();

		if (objects)
			new Thread({ _objects = getObjects(); }).start();

		ImageSurface scaled = ImageSurface.create(CairoFormat.RGB24, _img.getWidth(), _img.getHeight());
		auto ctx = Context.create(scaled);
		ctx.setSourcePixbuf(_img, 0, 0);
		ctx.rectangle(0, 0, _img.getWidth(), _img.getHeight());
		ctx.fill();
		ctx.destroy();

		_scaled = Pattern.createForSurface(scaled);
		_scaled.setFilter(CairoFilter.NEAREST);

		addOnDraw(&onDraw);
	}

	void finish()
	{
		stop = true;
		if (_onSelected !is null && _regions.length > 0)
		{
			_success = true;
			_onSelected(_img, _regions);
		}
		_window.close();
		Main.quit();
	}

	size_t getRegion(int x, int y)
	{
		foreach (i, region; _regions)
		{
			if (x >= region.x && x <= region.x + region.w && y >= region.y
					&& y <= region.y + region.h && region.valid)
				return i;
		}
		return -1;
	}

	size_t getObject(int x, int y)
	{
		foreach (i, region; _objects)
		{
			if (x >= region.x && x <= region.x + region.w && y >= region.y
					&& y <= region.y + region.h && region.valid)
				return i;
		}
		return -1;
	}

	bool onButtonRelease(Event event, Widget widget)
	{
		uint button;
		double x, y;
		if (event.getButton(button) && event.getCoords(x, y))
		{
			if (button == 1)
			{
				_lmb = false;
				if (abs(_startX - x) < 4 && abs(_startY - y) < 4)
				{
					size_t object;
					if ((object = getObject(cast(int) round(x), cast(int) round(y))) != -1)
					{
						_regions ~= _objects[object];
					}
				}
				else
				{
					_regions.fix();
					_regions.removeTiny();
					if (_fastCapture)
					{
						finish();
					}
				}
			}
			if (button == 3)
			{
				int rx = cast(int) round(x);
				int ry = cast(int) round(y);
				_selectedRegion = getRegion(rx, ry);
				if (_selectedRegion == -1)
				{
					stop = true;
					_window.close();
					Main.quit();
				}
				else
				{
					_regions[_selectedRegion].w = 0;
					_regions.removeTiny();
				}
			}
			return true;
		}
		ushort key;
		if (event.getKeycode(key))
		{
			if (key == 9) // Escape
			{
				stop = true;
				_window.close();
				Main.quit();
				return true;
			}
			if (key == 36) // Return
			{
				finish();
				return true;
			}

			GdkModifierType state;
			if (event.getState(state))
			{
				if ((state & GdkModifierType.CONTROL_MASK) != 0 && key == 54) // c
				{
					Clipboard.get(null).setText(_colorString, cast(int) _colorString.length);
					return true;
				}
			}

		}
		return false;
	}

	bool onButtonPress(Event event, Widget widget)
	{
		uint button;
		double x, y;
		if (event.getButton(button) && event.getCoords(x, y))
		{
			if (button == 1)
			{
				int rx = cast(int) round(x);
				int ry = cast(int) round(y);
				_startX = rx;
				_startY = ry;
				_selectedRegion = getRegion(rx, ry);
				if (_selectedRegion == -1)
				{
					_move = false;
					Region region;
					region.x = rx;
					region.y = ry;
					region.w = 0;
					region.h = 0;
					_regions ~= region;
					_selectedRegion = _regions.length - 1;
				}
				else
				{
					_move = true;
				}
				_lmb = true;
			}
			return false;
		}
		ushort key;
		if (event.getKeycode(key))
		{
			if (key == 111) // Up
			{
				Screen screen;
				int cx, cy;
				_mouse.getPosition(screen, cx, cy);
				_mouse.warp(screen, cx, cy - 1);
			}
			if (key == 113) // Left
			{
				Screen screen;
				int cx, cy;
				_mouse.getPosition(screen, cx, cy);
				_mouse.warp(screen, cx - 1, cy);
			}
			if (key == 116) // Down
			{
				Screen screen;
				int cx, cy;
				_mouse.getPosition(screen, cx, cy);
				_mouse.warp(screen, cx, cy + 1);
			}
			if (key == 114) // Right
			{
				Screen screen;
				int cx, cy;
				_mouse.getPosition(screen, cx, cy);
				_mouse.warp(screen, cx + 1, cy);
			}
			return false;
		}
		return true;
	}

	bool onMouseMove(Event event, Widget widget)
	{
		double x, y;
		if (event.getCoords(x, y))
		{
			moveMouse(x, y);
			return true;
		}
		return false;
	}

	bool onScroll(Event event, Widget widget)
	{
		GdkScrollDirection direction;
		if (event.getScrollDirection(direction))
		{
			if (direction == GdkScrollDirection.UP && _radius < 500)
				_radius += 5;
			else if (direction == GdkScrollDirection.DOWN && _radius > 50)
				_radius -= 5;
			return true;
		}
		return false;
	}

	void moveMouse(double x, double y)
	{
		int rx = cast(int) round(x);
		int ry = cast(int) round(y);

		_mx = rx;
		_my = ry;

		if (_lmb)
		{
			if (_move)
			{
				_regions[_selectedRegion].x = rx;
				_regions[_selectedRegion].y = ry;
			}
			else
			{
				_regions[_selectedRegion].w = rx - _regions[_selectedRegion].x;
				_regions[_selectedRegion].h = ry - _regions[_selectedRegion].y;
			}
		}
	}

	bool onDraw(Scoped!Context context, Widget widget)
	{
		context.setAntialias(CairoAntialias.NONE);

		context.setSourcePixbuf(_img, 0, 0);
		context.rectangle(0, 0, _img.getWidth(), _img.getHeight());
		context.fill();

		context.setSourceRgba(0, 0, 0, 0.7);
		context.rectangle(0, 0, _img.getWidth(), _img.getHeight());
		context.fill();

		context.setSourcePixbuf(_img, 0, 0);

		foreach (region; _regions)
		{
			if (region.valid)
			{
				region = region.fixCopy();
				context.rectangle(region.x, region.y, region.w, region.h);
				context.fill();
			}
		}

		context.setSourceRgb(1, 1, 1);

		context.setLineWidth(1);
		context.setDash([8, 8], _time);

		auto object = getObject(_mx, _my);

		if (object != -1)
		{
			auto r = _objects[object];
			context.moveTo(r.x + 1, r.y + 1);
			context.lineTo(r.x + r.w, r.y + 1);
			context.lineTo(r.x + r.w, r.y + r.h);
			context.lineTo(r.x + 1, r.y + r.h);
			context.lineTo(r.x + 1, r.y + 1);
			context.stroke();
		}

		foreach (r; _regions)
		{
			if (r.valid)
			{
				r = r.fixCopy();
				context.moveTo(r.x + 1, r.y + 1);
				context.lineTo(r.x + r.w, r.y + 1);
				context.lineTo(r.x + r.w, r.y + r.h);
				context.lineTo(r.x + 1, r.y + r.h);
				context.lineTo(r.x + 1, r.y + 1);
				context.stroke();
			}
		}

		context.moveTo(_mx, 0);
		context.lineTo(_mx, _img.getHeight());
		context.stroke();

		context.moveTo(0, _my);
		context.lineTo(_img.getWidth(), _my);
		context.stroke();

		int magOffX = radius + 8;
		int magOffY = radius + 8;

		auto color = _img.getColorAt(_mx, _my);
		if (color != _lastColor)
		{
			if ((color >> 24) != 0xFF)
				_colorString = format!`#%06x%02x`(color & 0xFFFFFF, color >> 24);
			else
				_colorString = format!`#%06x`(color & 0xFFFFFF);
			_lastColor = color;
		}

		if (_mx + 8 + radius + radius > _img.getWidth() && _mx > _img.getWidth() / 2)
			magOffX = -radius - 8;

		if (_my + 8 + radius + radius > _img.getHeight() && _my > _img.getHeight() / 2)
			magOffY = -radius - 8;

		context.arc(_mx + magOffX, _my + magOffY, radius, 0, 6.28318530718f);
		enum scale = 8;
		enum iScale = 1.0 / scale;
		context.scale(scale, scale);
		context.translate(-_mx * (1 - iScale) + magOffX * iScale, -_my * (1 - iScale) + magOffY * iScale);
		context.setSource(_scaled);
		context.fill();
		context.identityMatrix();

		context.setSourceRgb(1, 1, 1);
		context.setDash([scale, scale], magOffX);

		context.moveTo(_mx + magOffX - radius, _my + magOffY);
		context.lineTo(_mx + magOffX + radius, _my + magOffY);
		context.stroke();

		context.moveTo(_mx + magOffX, _my + magOffY - radius);
		context.lineTo(_mx + magOffX, _my + magOffY + radius);
		context.stroke();

		context.translate(_mx + magOffX - radius, _my + magOffY + radius);
		context.setSourceRgb(((_lastColor >> 16) & 0xFF) / 255.0,
				((_lastColor >> 8) & 0xFF) / 255.0, (_lastColor & 0xFF) / 255.0);
		context.rectangle(0, -20, 20, 20);
		context.fill();
		context.translate(25, 0);
		context.setSourceRgb(0, 0, 0);
		context.setFontSize(20);
		context.showText(_colorString);
		context.fill();
		context.setSourceRgb(1, 1, 1);
		context.translate(-1, -1);
		context.showText(_colorString);
		context.fill();
		context.identityMatrix();

		_time++;
		if (!stop)
			this.queueDraw();
		return true;
	}

	@property ref auto onSelected()
	{
		return _onSelected;
	}

	@property ref auto fastCapture()
	{
		return _fastCapture;
	}

	@property ref int radius()
	{
		return _radius;
	}

	@property bool success()
	{
		return _success;
	}
}

uint getColorAt(Pixbuf pixbuf, int x, int y)
{
	if (x < 0 || y < 0)
		return 0;
	int w = pixbuf.getWidth();
	int h = pixbuf.getHeight();
	if (x >= w || y >= h)
		return 0;

	int n = pixbuf.getNChannels();

	auto pixels = pixbuf.getPixelsWithLength();
	pixels = pixels[pixbuf.getRowstride() * y + x * n .. $];
	pixels = pixels[0 .. n];

	if (n == 3)
		return 0xFF000000U | (pixels[0] << 16) | (pixels[1] << 8) | pixels[2];
	else if (n == 4)
		return (pixels[3] << 24) | (pixels[0] << 16) | (pixels[1] << 8) | pixels[2];
	else
		return 0;
}
