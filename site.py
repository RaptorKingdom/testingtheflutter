# site.py
import logging
import sys
import os
import asyncio
import re
from random import random as uniform, sample, choice
from time import sleep
import requests
from urllib.parse import quote, urlencode
from flask import Flask, render_template_string, request, url_for, send_from_directory, jsonify
from playwright.async_api import async_playwright

# ------------------ Logging Setup ------------------
network_logger = logging.getLogger('request-logger')
network_logger.setLevel(logging.INFO)
file_handler = logging.FileHandler('network-log.log', mode='w')
network_formatter = logging.Formatter('%(asctime)s - %(message)s', '%H:%M:%S')
file_handler.setFormatter(network_formatter)
network_logger.addHandler(file_handler)

info_logger = logging.getLogger('Image Generation')
info_logger.setLevel(logging.INFO)
stdout_handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s', '%H:%M:%S')
stdout_handler.setFormatter(formatter)
info_logger.addHandler(stdout_handler)

# ------------------ Wordlist ------------------
class MyWordlist:
    def __init__(self):
        self.wordlist = ["Dragon", "Castle", "Moon", "Forest", "Apple", "Fish", "Green", "Banana", "Queen Elizabeth I", "Inspiration"]

    def get_prompt(self, number=10):
        return ', '.join(sample(self.wordlist, number))

# ------------------ Styles ------------------
styles = {
    'no-style': ('', ''),
    'cinematic': (
        'cinematic shot, dynamic lighting, 75mm, Technicolor, Panavision, cinemascope, sharp focus, fine details, 8k, HDR, realism, realistic, key visual, film still, superb cinematic color grading, depth of field',
        'bad lighting, low-quality, deformed, text, poorly drawn, holding camera, bad art, bad angle, boring, low-resolution, worst quality, bad composition, disfigured'
    ),
    'traditional-japanese': (
        'in ukiyo-e art style, traditional japanese masterpiece',
        'blurry, low resolution, worst quality, fuzzy'
    )
}

# ------------------ Helper encode ------------------
def encode(prompt):
    replacement_dict = {
        ' ': r'%20',
        ',': r'%2C',
    }
    translation_table = str.maketrans(replacement_dict)
    output_string = r'%27' + prompt.translate(translation_table)
    return output_string

# ------------------ Image Generator ------------------
def image_generator(
        base_filename='',
        amount=1,
        prompt='RANDOM',
        prompt_size=10,
        negative_prompt='',
        style='RANDOM',
        resolution='512x768',
        guidance_scale=7
):
    create_url = 'https://image-generation.perchance.org/api/generate'
    download_url = 'https://image-generation.perchance.org/api/downloadTemporaryImage'

    if prompt == 'RANDOM':
        wordlist = MyWordlist()
        prompt_base = wordlist.get_prompt(prompt_size)
    else:
        prompt_base = prompt
    if style == 'RANDOM':
        list_of_styles = list(styles.keys())
        style_choice = choice(list_of_styles)
        style_pair = styles[style_choice]
    else:
        try:
            style_choice = style
            style_pair = styles[style_choice]
        except KeyError:
            raise Exception(f'Style choice {style} was not recognized. Check styles.')

    prompt_style = styles[style_choice][0]
    negative_prompt_style = styles[style_choice][1]

    prompt_query = quote('\'' + prompt_base + ', ' + prompt_style)
    negative_prompt_query = quote('\'' + negative_prompt + ', ' + negative_prompt_style)
    info_logger.info(f'Selected prompt {prompt_base} and style {style_choice}')

    for idx in range(1, amount + 1):
        user_key = get_key()
        request_id = uniform()
        cache_bust = uniform()

        create_params = {
            'prompt': prompt_query,
            'negativePrompt': negative_prompt_query,
            'userKey': user_key,
            '__cache_bust': cache_bust,
            'seed': '-1',
            'resolution': resolution,
            'guidanceScale': str(guidance_scale),
            'channel': 'ai-text-to-image-generator',
            'subChannel': 'public',
            'requestId': request_id
        }
        create_params_str = urlencode(create_params, safe=':%')

        create_response = requests.get(create_url, params=create_params_str)

        if 'invalid_key' in create_response.text:
            raise Exception('Image could not be generated (invalid key).')

        exit_flag = False
        while not exit_flag:
            try:
                image_id = create_response.json()['imageId']
                exit_flag = True
            except KeyError:
                info_logger.info('Waiting for previous request to finish...')
                sleep(8)
                create_response = requests.get(create_url, params=create_params_str)

        download_params = {
            'imageId': image_id
        }
        download_response = requests.get(download_url, params=download_params)

        filename = f'generated-pictures/{base_filename}{idx}.jpeg' if base_filename else f'generated-pictures/{image_id}.jpeg'
        os.makedirs('generated-pictures', exist_ok=True)
        with open(filename, 'wb') as file:
            file.write(download_response.content)

        info_logger.info(f'Created picture {idx}/{amount} ({filename=})')
        yield {
            'filename': filename,
            'prompt': prompt_base,
            'negative_prompt': negative_prompt
        }

# ------------------ Key Management ------------------
async def get_url_data():
    url_data = []
    async with async_playwright() as p:
        browser = await p.firefox.launch(headless=True)
        page = await browser.new_page()

        def request_handler(request):
            request_info = f'{request.method} {request.url} \n'
            network_logger.info(request_info)
            url_data.append(request.url)

        page.on("request", request_handler)

        await page.goto('https://perchance.org/ai-text-to-image-generator')

        iframe_element = await page.query_selector('xpath=//iframe[@src]')
        frame = await iframe_element.content_frame()
        await frame.click('xpath=//button[@id="generateButtonEl"]')

        key = None
        while key is None:
            pattern = r'userKey=([a-f\d]{64})'
            all_urls = ''.join(url_data)
            keys = re.findall(pattern, all_urls)
            if keys:
                key = keys[0]
            url_data = []
            await asyncio.sleep(1)

        await browser.close()
    return key

def get_key():
    # Check if last_key.txt exists and is valid
    key = None
    if os.path.exists('last_key.txt'):
        with open('last_key.txt', 'r') as file:
            line = file.readline().strip()
        if line:
            verification_url = 'https://image-generation.perchance.org/api/checkVerificationStatus'
            user_key = line
            cache_bust = uniform()
            verification_params = {
                'userKey': user_key,
                '__cacheBust': cache_bust
            }
            response = requests.get(verification_url, params=verification_params)
            if 'not_verified' not in response.text:
                key = line
                info_logger.info(f'Found working key {key[:10]}... in file.')
                return key

    info_logger.info('Key no longer valid. Looking for a new key...')
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
    key = loop.run_until_complete(get_url_data())

    info_logger.info(f'Found key {key[:10]}...')
    with open('last_key.txt', 'w') as file:
        file.write(key)
    return key

# ------------------ Flask App ------------------
app = Flask(__name__)
app.config['GENERATED_FOLDER'] = os.path.join(os.getcwd(), 'generated-pictures')

# Embedded HTML template
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Image Generator</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .card {
            backdrop-filter: blur(10px);
            background: rgba(255, 255, 255, 0.9);
        }
        .image-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
            gap: 1rem;
        }
    </style>
</head>
<body class="font-sans antialiased">
    <div class="container mx-auto px-4 py-8">
        <h1 class="text-4xl font-bold text-white text-center mb-8 drop-shadow-lg">
            🎨 AI Image Generator
        </h1>

        <div class="card rounded-2xl shadow-2xl p-6 md:p-8 max-w-2xl mx-auto">
            <form method="POST" class="space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Prompt</label>
                        <input type="text" name="prompt" value="RANDOM" 
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <p class="text-xs text-gray-500 mt-1">Leave "RANDOM" for random prompt</p>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Negative Prompt</label>
                        <input type="text" name="negative_prompt" value="nudity text" 
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Style</label>
                        <select name="style" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                            <option value="RANDOM">Random</option>
                            <option value="no-style">No Style</option>
                            <option value="cinematic">Cinematic</option>
                            <option value="traditional-japanese">Traditional Japanese</option>
                        </select>
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Resolution</label>
                        <input type="text" name="resolution" value="512x768" 
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Number of Images</label>
                        <input type="number" name="amount" value="1" min="1" max="10"
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Prompt Size (if random)</label>
                        <input type="number" name="prompt_size" value="10" min="1" max="20"
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Guidance Scale</label>
                        <input type="number" step="0.1" name="guidance_scale" value="7" min="1" max="20"
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700">Base Filename (optional)</label>
                        <input type="text" name="base_filename" value=""
                               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    </div>
                </div>

                <button type="submit" 
                        class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                    Generate Images
                </button>
            </form>
        </div>

        {% if error %}
        <div class="mt-6 max-w-2xl mx-auto bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative" role="alert">
            <strong class="font-bold">Error!</strong>
            <span class="block sm:inline">{{ error }}</span>
        </div>
        {% endif %}

        {% if images %}
        <div class="mt-10">
            <h2 class="text-2xl font-bold text-white mb-4">Generated Images</h2>
            <div class="image-grid">
                {% for img in images %}
                <div class="bg-white rounded-lg overflow-hidden shadow-lg hover:shadow-2xl transition-shadow duration-300">
                    <img src="{{ img.url }}" alt="Generated image" class="w-full h-64 object-cover">
                    <div class="p-4">
                        <p class="text-sm text-gray-600"><strong>Prompt:</strong> {{ img.prompt }}</p>
                        <p class="text-sm text-gray-500"><strong>Negative:</strong> {{ img.negative_prompt }}</p>
                    </div>
                </div>
                {% endfor %}
            </div>
        </div>
        {% endif %}
    </div>
</body>
</html>
'''

@app.route('/generated/<filename>')
def serve_image(filename):
    return send_from_directory(app.config['GENERATED_FOLDER'], filename)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        try:
            base_filename = request.form.get('base_filename', '').strip()
            amount = int(request.form.get('amount', 1))
            prompt = request.form.get('prompt', 'RANDOM').strip()
            prompt_size = int(request.form.get('prompt_size', 10))
            negative_prompt = request.form.get('negative_prompt', 'nudity text').strip().replace(' ', ', ')
            style = request.form.get('style', 'RANDOM')
            resolution = request.form.get('resolution', '512x768')
            guidance_scale = float(request.form.get('guidance_scale', 7))

            # Validate resolution
            if not re.match(r'\d{2,4}x\d{2,4}', resolution):
                raise ValueError('Invalid resolution format. Use e.g. 512x768.')

            generator = image_generator(
                base_filename=base_filename,
                amount=amount,
                prompt=prompt,
                prompt_size=prompt_size,
                negative_prompt=negative_prompt,
                style=style,
                resolution=resolution,
                guidance_scale=guidance_scale
            )

            images = []
            for result in generator:
                filename = os.path.basename(result['filename'])
                url = url_for('serve_image', filename=filename)
                images.append({
                    'url': url,
                    'prompt': result['prompt'],
                    'negative_prompt': result['negative_prompt']
                })

            return render_template_string(HTML_TEMPLATE, images=images, error=None)
        except Exception as e:
            error_msg = str(e)
            info_logger.error(f'Error: {error_msg}')
            return render_template_string(HTML_TEMPLATE, images=None, error=error_msg)

    # GET request - show form
    return render_template_string(HTML_TEMPLATE, images=None, error=None)

@app.route('/api/status')
def api_status():
    status = {
        'status': 'running',
        'generated_images_count': len(os.listdir(app.config['GENERATED_FOLDER'])) if os.path.exists(app.config['GENERATED_FOLDER']) else 0,
        'last_key_exists': os.path.exists('last_key.txt')
    }
    return jsonify(status)

if __name__ == '__main__':
    os.makedirs('generated-pictures', exist_ok=True)
    app.run(debug=True, host='0.0.0.0', port=5000)