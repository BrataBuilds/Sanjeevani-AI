# 1. Features for the app that will be used by the user 
## 1.1. Issues
Write your issues here
## 1.2. MVP 
The following features are for the bare bones MVP, minimum amount of features required for the demonstration
1. **First time boot**:
    1. **Login/Registration page**, login done via
        - User name / password (App lock)
        - JWT Auth
        - Adhar login verification (UI only)
        - Profile page, (all details stored locally until user searches for hospitals)
    1. **Personal details to store:**
        Fields not marked (if any) are mandatory.
        - **Profile picture, Name, Age, DOB, Address, phone, email, gender, blood type, insurance provider** (if any), **policy number** (if any), **location data, preferred hospitals** (if any), **list of existing known diseases/ allergies, genetic disorders** (if any, multi-input)
        - **Relative/Guardian/Sibling/Spouse details, Name, Contact and Type of relation** (*They are automatically informed if ward is admitted to a hospital*) (Multi-input, *heavily suggest user to keep at least one input*)
        - **Medical history:** Images, scanned pdfs, document label *(user describes type of document, such that report, blood test, xray etc*)
2. **AI Chat window:**
    - Normal text window
    - Add mock buttons to accept images and voice input  (Just for show as of now)
    - A button at the top that selects language 
    - Chat history 
    - MCQ questions UI asked by the LLM  
    - UI for LLM recommended hospitals
    - Status bar for getting updates from the hospital
3. **Hospital / Doctor chat window :**
    - Same as the LLM just having a different backend.
    - Will have different icons for good UX.
    - Doctors and hospitals will have their respective pfps.
4. **User profile page:**
    - Just display the data collected during login.
    - Option to view and edit data
    - A button to view collected medical bills and info.
Two windows to clearly distinguish between who is talking to whom.
## 1.3. Future Plans  
- Multi-user setup to allow proxies for friends and family
- Login, details Integration with government schemes (Ayushman Bharat, CGHS, state health schemes)
- SMS/IVR fallback for patients without a smartphone or reliable data (useful for proxies)
- Notification system and auto calendar synchronisation for appointment scheduling and reminders
- Post-visit follow-up chatbot and medication reminders
- Optional teleconsultation for cases that don't need a physical visit at all
- Ambulance map eta tracker for emergencies
- Pharmacy integration and e-prescriptions