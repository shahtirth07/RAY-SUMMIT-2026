from urllib.parse import urljoin
from openai import OpenAI

API_KEY = "FAKE_KEY"
BASE_URL = "http://localhost:8000"

client = OpenAI(base_url=urljoin(BASE_URL, "v1"), api_key=API_KEY)

response = client.chat.completions.create(
    model="qwen3.6-27b",
    messages=[{"role": "user", "content": "Write a Python one-liner to flatten a list of lists."}],
    stream=True,
)

for chunk in response:
    content = chunk.choices[0].delta.content
    if content:
        print(content, end="", flush=True)
