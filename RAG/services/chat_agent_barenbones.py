"""Custom Chat Agent, made using standard google genai api"""
from google import genai
from config.config import settings
GEMINI_API = settings.gemini_api
client  = genai.Client(api_key=GEMINI_API,)
interaction = client.interactions.create(
    model='gemma-4-31b-it',
    input='my name is pareni, what was my last message?'
    syste
)
print(interaction.output_text)