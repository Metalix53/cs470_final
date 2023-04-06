#include <SFML/Graphics.hpp>
#include <math.h>
#include <iostream>
#include <chrono>

__device__ void HSVtoRGB(int* red, int* green, int* blue, float H, float S, float V);
__device__ double mandelIter(double cx, double cy, int maxIter);
double normalize(double value, double localMin, double localMax, double min, double max);
sf::Texture mandelbrot(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations);
__global__ void mandel_kernel(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations, sf::Uint8* pixels);

int main()
{
	unsigned int width = 1600;
	unsigned int height = 900;

	sf::RenderWindow window(sf::VideoMode(width, height), "mandelbrot");
	
	window.setFramerateLimit(144);

	sf::Texture mandelTexture;
	sf::Sprite mandelSprite;

	sf::RectangleShape zoomBorder(sf::Vector2f(width / 8, height / 8));
	zoomBorder.setFillColor(sf::Color(0, 0, 0, 0));
	zoomBorder.setOutlineColor(sf::Color(255, 255, 255, 128));
	zoomBorder.setOutlineThickness(1.0f);
	zoomBorder.setOrigin(sf::Vector2f(zoomBorder.getSize().x / 2, zoomBorder.getSize().y / 2));

	double oxmin = -2.4;
	double oxmax = 1.0;
	double oyRange = (oxmax - oxmin) * height / width;
	double oymin = -oyRange / 2;
	double oymax = oyRange / 2;

	double xmin = oxmin;
	double xmax = oxmax;
	double yRange = oyRange;
	double ymin = oymin;
	double ymax = oymax;

	int recLevel = 1;
	int precision = 64;

	mandelTexture = mandelbrot(width, height, oxmin, oxmax, oymin, oymax, precision);

	sf::Text zoomText, precText;
	zoomText.setFillColor(sf::Color::White);
	precText.setFillColor(sf::Color::White);
	zoomText.setCharacterSize(24);
	precText.setCharacterSize(24);

	while (window.isOpen())
	{
		sf::Event evnt;
		while (window.pollEvent(evnt))
		{
			switch (evnt.type)
			{
			case sf::Event::Closed:
				window.close();
				break;
			case sf::Event::KeyReleased:
				if (evnt.key.code == sf::Keyboard::Key::O)
				{
					precision = 64;

					xmin = oxmin;
					xmax = oxmax;
					yRange = oyRange;
					ymin = oymin;
					ymax = oymax;
				}

				mandelTexture = mandelbrot(width, height, xmin, xmax, ymin, ymax, precision);
				break;
			case sf::Event::MouseWheelScrolled:
				if (evnt.mouseWheelScroll.delta <= 0)
				{
					precision /= 2;
					if (precision <= 4)
					{
						exit(0);
					}
				}
				else
				{
					precision *= 2;
				}
				mandelTexture = mandelbrot(width, height, xmin, xmax, ymin, ymax, precision);
				break;
			}
		}

		if (sf::Mouse::isButtonPressed(sf::Mouse::Left))
		{
			recLevel++;

			double x = zoomBorder.getPosition().x - zoomBorder.getSize().x / 2;
			double y = zoomBorder.getPosition().y - zoomBorder.getSize().y / 2;

			double x2 = x + zoomBorder.getSize().x;
			double y2 = y + zoomBorder.getSize().y;

			//from px range to grid range
			double normX = normalize(x, 0.0, width, xmin, xmax);
			double normY = normalize(y, 0.0, height, ymin, ymax);

			double widthNorm = normalize(x2, 0.0, width, xmin, xmax);
			double heightNorm = normalize(y2, 0.0, height, ymin, ymax);

			xmin = normX;
			xmax = widthNorm;
			ymin = normY;
			ymax = heightNorm;

			mandelTexture = mandelbrot(width, height, xmin, xmax, ymin, ymax, precision);
		}

		zoomText.setString("Zoom: " + std::to_string(pow(8, recLevel - 1)));
		precText.setString("Max. Iterations: " + std::to_string(precision));
		precText.setPosition(sf::Vector2f(0, 32));

		zoomBorder.setPosition(sf::Mouse::getPosition(window).x, sf::Mouse::getPosition(window).y);


		mandelSprite.setTexture(mandelTexture);

		window.clear(sf::Color::White);

		window.draw(mandelSprite);
		window.draw(zoomText);
		window.draw(precText);
		window.draw(zoomBorder);

		window.display();
	}

	return 0;
}

double normalize(double value, double localMin, double localMax, double min, double max)
{
	double normalized = (value - localMin) / (localMax - localMin);
	normalized = normalized * (max - min);
	normalized += min;
	return normalized;
}

__device__
double mandelIter(double cx, double cy, int maxIter) {
	double x = 0.0;
	double y = 0.0;
	double xx = 0.0;
	double yy = 0.0;
	double xy = 0.0;

	double i = maxIter;
	while (i-- && xx + yy <= 4) {
		xy = x * y;
		xx = x * x;
		yy = y * y;
		x = xx - yy + cx;
		y = xy + xy + cy;
	}
	return maxIter - i;
}


sf::Texture mandelbrot(int width, int height, double xmin, double xmax, double ymin, double ymax, int precision)
{
	sf::Texture texture;
	texture.create(width, height);

	sf::Uint8* pixels;

	cudaMallocManaged(&pixels, sizeof(sf::Uint8) * (width * height * 4));

	auto start = std::chrono::high_resolution_clock::now();
	mandel_kernel << <512, 512 >> > (width, height, xmin, xmax, ymin, ymax, precision, pixels);
	cudaDeviceSynchronize();
	auto end = std::chrono::high_resolution_clock::now();
	auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start);
	printf("CUDA PREC: %d TIME: %8.4fs\n", precision, elapsed.count() * 1e-9);


	texture.update(pixels, width, height, 0, 0);

	cudaFree(pixels);

	return texture;
}


__global__
void mandel_kernel(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations, sf::Uint8* pixels)
{
	int i = (blockIdx.y * blockDim.y + threadIdx.y) * blockDim.x * gridDim.x +
		(blockIdx.x * blockDim.x + threadIdx.x);
	for (; i < width * height; i += blockDim.x * gridDim.x * blockDim.y * gridDim.y)
	{
		int row = i / width;
		int col = i % width;
		double x = xmin + (xmax - xmin) * col / (width - 1.0);
		double y = ymin + (ymax - ymin) * row / (height - 1.0);

		double i = mandelIter(x, y, iterations);

		int ppos = 4 * (width * row + col);

		int hue = (int)(255 * i / iterations);
		int sat = 100;
		int val = (i > iterations) ? 0 : 100;
		int R;
		int G;
		int B;
		HSVtoRGB(&R, &G, &B, hue, sat, val);
		pixels[ppos] = B;
		pixels[ppos + 1] = G;
		pixels[ppos + 2] = R;
		pixels[ppos + 3] = 255;
	}
}

__device__
void HSVtoRGB(int* red, int* green, int* blue, float H, float S, float V)
{
	if (H > 360 || H < 0 || S>100 || S < 0 || V>100 || V < 0) {
		*red = 0;
		*green = 0;
		*blue = 0;
		return;
	}
	float s = S / 100;
	float v = V / 100;
	float C = s * v;
	float X = C * (1 - abs(fmod((double)(H / 60.0),(double) 2) - 1));
	float m = v - C;
	float r, g, b;
	if (H >= 0 && H < 60) {
		r = C, g = X, b = 0;
	}
	else if (H >= 60 && H < 120) {
		r = X, g = C, b = 0;
	}
	else if (H >= 120 && H < 180) {
		r = 0, g = C, b = X;
	}
	else if (H >= 180 && H < 240) {
		r = 0, g = X, b = C;
	}
	else if (H >= 240 && H < 300) {
		r = X, g = 0, b = C;
	}
	else {
		r = C, g = 0, b = X;
	}
	int R = (r + m) * 255;
	int G = (g + m) * 255;
	int B = (b + m) * 255;
	*red = R;
	*green = G;
	*blue = B;
}