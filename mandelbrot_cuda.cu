#include <SFML/Graphics.hpp>
#include <math.h>
#include <iostream>
#include "timer.h"

__device__ void HSVtoRGB(int* red, int* green, int* blue, float H, float S, float V);
__device__ double mandelIter(double cx, double cy, int maxIter);
double normalize(double value, double localMin, double localMax, double min, double max);
sf::Texture mandelbrot(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations);
sf::Texture julia(int width, int height, double cRe, double cIm, int iterations);
__global__ void mandel_kernel(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations, sf::Uint8* pixels);
__global__ void julia_kernel(int width, int height, double cRe, double cIm, int iterations, sf::Uint8* pixels);
sf::Texture transform_pixels(int width, int height);
__global__ void transform_kernel(int width, int height, sf::Uint8* pixels);

sf::Uint8* current_pixels;
bool makeJulia = true;
int transform_count = 0;
int main()
{
	unsigned int width = 1600;
	unsigned int height = 900;
	// for color transformations, keep a copy of the pixels in vram.
	cudaMallocManaged(&current_pixels, sizeof(sf::Uint8)*(width * height * 4));
	sf::RenderWindow window(sf::VideoMode(width, height), "mandelbrot");

	window.setFramerateLimit(144);

	sf::Texture mandelTexture;
	sf::Sprite mandelSprite;

  sf::RectangleShape zoomBorder(sf::Vector2f(width / 8, height / 8));
	zoomBorder.setFillColor(sf::Color(0, 0, 0, 0));
	zoomBorder.setOutlineColor(sf::Color(255, 255, 255, 128));
	zoomBorder.setOutlineThickness(1.0f);
	zoomBorder.setOrigin(sf::Vector2f(zoomBorder.getSize().x / 2, zoomBorder.getSize().y / 2));

  double cRe = -.7;
  double cIm = .27015;

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
	int precision = 512;

	if (makeJulia)
  {
    mandelTexture = julia(width, height, cRe, cIm, precision);
  }
  else
  {
    mandelTexture = mandelbrot(width, height, oxmin, oxmax, oymin, oymax, precision);
  }



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
					recLevel = 1;
					precision = 64;

					xmin = oxmin;
					xmax = oxmax;
					yRange = oyRange;
					ymin = oymin;
					ymax = oymax;
				}
				else if (evnt.key.code == sf::Keyboard::Key::T) 
				{
          START_TIMER(prec);
					mandelTexture = transform_pixels(width, height);
          	STOP_TIMER(prec);
  	        printf("Transform TIME: %8.4fs\n", GET_TIMER(prec));
            transform_count = (transform_count + 1) % 3;
					break;
				}
        else if (evnt.key.code == sf::Keyboard::Key::A)
        {
          if(makeJulia)
          {
            cRe-=.01;
            cIm-=.01;
            mandelTexture = julia(width, height, cRe, cIm, precision);
            		  			              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
          }
        }
        else if (evnt.key.code == sf::Keyboard::Key::D)
        {
          if(makeJulia)
          {
            cRe+=.01;
            cIm+=.01;
            mandelTexture = julia(width, height, cRe, cIm, precision);
            		  			              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
          }
        }
        else if (evnt.key.code == sf::Keyboard::Key::W)
        {
          if(makeJulia)
          {
            cRe+=.01;
            cIm-=.01;
            mandelTexture = julia(width, height, cRe, cIm, precision);
            		  			              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
          }
        }
        else if (evnt.key.code == sf::Keyboard::Key::S)
        {
          if(makeJulia)
          {
            cRe-=.01;
            cIm+=.01;
            mandelTexture = julia(width, height, cRe, cIm, precision);
            		  			              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
          }
        }
        else if (evnt.key.code == sf::Keyboard::Key::J)
        {
          if(makeJulia)
          {
            makeJulia = false;
            mandelTexture = mandelbrot(width, height, oxmin, oxmax, oymin, oymax, precision);
          }
          else
          {
            makeJulia = true;
            mandelTexture = julia(width, height, cRe, cIm, precision);
          }
        }
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
				if (makeJulia)
        {
          mandelTexture = julia(width, height, cRe, cIm, precision);
              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
        }
        else
        {
          mandelTexture = mandelbrot(width, height, xmin, xmax, ymin, ymax, precision);
              for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
        }	
				break;
			}
		}

    if (sf::Mouse::isButtonPressed(sf::Mouse::Left))
		{
      if (!makeJulia)
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
                      for(int i = 0; i < transform_count; i++)
              {
                mandelTexture = transform_pixels(width, height);
              }
      }
		}


    zoomBorder.setPosition(sf::Mouse::getPosition(window).x, sf::Mouse::getPosition(window).y);

		mandelSprite.setTexture(mandelTexture);
		window.clear(sf::Color::White);
		window.draw(mandelSprite);
    if (!makeJulia)
    {
      window.draw(zoomBorder);
    }

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

  cudaMallocManaged(&pixels, sizeof(sf::Uint8)*(width * height * 4));

  START_TIMER(prec);
  mandel_kernel<<<512, 512>>>(width, height, xmin, xmax, ymin, ymax, precision, pixels);
  cudaDeviceSynchronize();
  STOP_TIMER(prec);
  printf("PREC: %d TIME: %8.4fs\n", precision,  GET_TIMER(prec));


	texture.update(pixels, width, height, 0, 0);
	// update current pixels with the new pixels
	cudaMemcpy(current_pixels, pixels, sizeof(sf::Uint8)*(width * height * 4), cudaMemcpyDeviceToDevice);
	cudaFree(pixels);

	return texture;
}

sf::Texture transform_pixels(int width, int height) {

	sf::Texture texture;
	texture.create(width, height);
	// kernel will update pixels.
	transform_kernel<<<512, 512>>>(width, height, current_pixels);
	cudaDeviceSynchronize();
	texture.update(current_pixels, width, height, 0, 0);
	return texture;
}

__global__ void transform_kernel(int width, int height, sf::Uint8* pixels) {
int transform_const = 50;
int i = blockIdx.x * blockDim.x + threadIdx.x;
	for (; i < width * height; i += blockDim.x * gridDim.x)
	{
      int row = i / width;
      int col = i % width;
      int ppos = 4 * (width * row + col);
      double zx = 1.5 * (col - width / 2) / (.5 * width);
      double zy = (row - height / 2) / (.5 * height);
      sf::Uint8 tmp_red = pixels[ppos];
      sf::Uint8 tmp_blue = pixels[ppos + 1];
      sf::Uint8 tmp_green = pixels[ppos + 2];

      pixels[ppos] = tmp_blue;
      pixels[ppos + 1] = tmp_green;
      pixels[ppos + 2] = tmp_red;
	    pixels[ppos + 3] = 255;
    }
}




sf::Texture julia(int width, int height, double cRe, double cIm, int iterations)
{
  sf::Texture texture;
  texture.create(width, height);

  sf::Uint8* pixels;

  cudaMallocManaged(&pixels, sizeof(sf::Uint8)*(width * height * 4));

  START_TIMER(prec);
  julia_kernel<<<512,512>>>(width, height, cRe, cIm, iterations, pixels);
  cudaDeviceSynchronize();
  STOP_TIMER(prec);
  printf("PREC: %d TIME: %8.4fs\n", iterations,  GET_TIMER(prec));

  texture.update(pixels, width, height, 0, 0);
	// update current pixels with the new pixels
	cudaMemcpy(current_pixels, pixels, sizeof(sf::Uint8)*(width * height * 4), cudaMemcpyDeviceToDevice);
	cudaFree(pixels);

	return texture;
}



__global__
void julia_kernel(int width, int height, double cRe, double cIm, int iterations, sf::Uint8* pixels)
{
  int i = blockIdx.x * blockDim.x + threadIdx.x;
	for (; i < width * height; i += blockDim.x * gridDim.x)
	{
      int row = i / width;
      int col = i % width;
      int ppos = 4 * (width * row + col);
      double zx = 1.5 * (col - width / 2) / (.5 * width);
      double zy = (row - height / 2) / (.5 * height);

      int i;

      for (i = 0; i < iterations; i++)
      {
        double oldzx = zx;
        double oldzy = zy;

        zx = oldzx * oldzx - oldzy * oldzy + cRe;
        zy = 2 * oldzx * oldzy + cIm;

        if((zx * zx + zy * zy) > 4) break;
      }
      int R, G, B;
      HSVtoRGB(&R, &G, &B, (int)(255 * i / iterations), 100, (i > iterations) ? 0 : 100);
      pixels[ppos] = B;
			pixels[ppos + 1] = G;
			pixels[ppos + 2] = G * 2;
			pixels[ppos + 3] = 255;
  }
}


__global__
void mandel_kernel(int width, int height, double xmin, double xmax, double ymin, double ymax, int iterations, sf::Uint8* pixels)
{
  int i = blockIdx.x * blockDim.x + threadIdx.x;
	for (; i < width * height; i += blockDim.x * gridDim.x)
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
    int R, G, B;
    HSVtoRGB(&R, &G, &B, hue, sat, val);
    pixels[ppos] = B;
    pixels[ppos + 1] = G;
    pixels[ppos + 2] = G * 2;
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
	float X = C * (1 - abs(fmodf(H / 60.0, 2) - 1));
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
