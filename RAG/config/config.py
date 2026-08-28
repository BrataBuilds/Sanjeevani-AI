from pydantic_settings import BaseSettings, SettingsConfigDict
class Settings(BaseSettings):
    gemini_api : str
    db_url : str
    db_table : str = "chat_sessions"
    # Overridable because the default is the weak point in this service. Gemma on
    # the Gemini API handles tool use plus a nested output schema poorly, and the
    # failure mode is a turn that names an action and omits its payload -- see
    # services/turn.py. Point GEMINI_MODEL at a function-calling model to fix it.
    gemini_model : str = "gemma-4-31b-it"
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8')
settings  = Settings()