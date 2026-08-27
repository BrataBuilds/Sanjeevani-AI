from services import database
import uuid 
import datetime
# Test if the database is being created properly.
database.initialize()
session = database.add_session()
print(session)
print(type(session))
all_sessions  = database.all_sessions()
print(session)
print(type(all_sessions))
session_details = database.session_details(session)
print(session_details)
print(type(session_details))