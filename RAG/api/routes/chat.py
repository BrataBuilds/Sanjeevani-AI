from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import ValidationError

import services.database as db
import services.report as report
from schemas.chat import ChatEntry, ChatResponse, UserPrompt, HistoryResponse
from schemas.triage import AgentTurn
from services.chat_agent import get_agent
from services.knowledge import check_symptoms

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
async def chat(prompt: UserPrompt):
    session_id = db.add_session(str(prompt.session_id) if prompt.session_id else None)
    report.init_session_state(session_id)
    state = report.get_session_state(session_id)

    force_report = report.force_report(state, prompt.user_query)
    turn_message = report.build_turn_message(prompt.user_query, state, force_report)

    try:
        agent, session_id = await get_agent(session_id=session_id)
        run_response = await agent.arun(turn_message)
        content = run_response.content
        turn = (
            content
            if isinstance(content, AgentTurn)
            else AgentTurn.model_validate_json(content)
            if isinstance(content, str)
            else AgentTurn.model_validate(content)
        )
    except ValidationError as e:
        raise HTTPException(502, detail=f"Agent returned an invalid triage response: {str(e)}")
    except Exception as e:
        raise HTTPException(502, detail=f"Agent couldn't be called. Check if API has been provided or not, more details: {str(e)}")

    if turn.action == "ask_question" and turn.follow_up is None:
        raise HTTPException(502, detail="Agent chose to ask a question but produced no follow-up.")
    if turn.action == "generate_report" and turn.report is None:
        raise HTTPException(502, detail="Agent chose to generate a report but produced none.")

    confirmed_symptoms = check_symptoms(turn.identified_symptoms)
    merged_symptoms, server_urgency_score, urgency_breakdown = report.apply_confirmed_symptoms(
        state["identified_symptoms"],
        state["total_urgency_score"],
        confirmed_symptoms,
    )
    all_confirmed_symptoms = check_symptoms(merged_symptoms)
    urgency_breakdown = [
        float(symptom["urgency_score"]) for symptom in all_confirmed_symptoms
    ]
    turn.running_urgency_score = server_urgency_score
    if turn.report is not None:
        turn.report = report.apply_server_urgency(
            turn.report,
            server_urgency_score,
            urgency_breakdown,
        )
        if turn.action == "generate_report":
            report.save_report(session_id, turn.report)

    user_time = datetime.now(timezone.utc)
    db.add_entry(session_id=session_id, role="user", content=prompt.user_query, timestamp=user_time.isoformat())
    assistant_time = datetime.now(timezone.utc)
    db.add_entry(session_id, role="assistant", content=turn.model_dump_json(), timestamp=assistant_time.isoformat())

    questions_asked = state["questions_asked"] + (1 if turn.action == "ask_question" else 0)
    new_status = "completed" if turn.action == "generate_report" else "in_progress"
    report.update_session_state(session_id, server_urgency_score, questions_asked, merged_symptoms, status=new_status)

    if turn.action == "ask_question":
        response_type, content = "mcq", turn.follow_up
    else:
        response_type = "text"
        content = (
            f"Your preliminary report is ready. Recommended specialty: "
            f"{turn.report.recommended_specialty}. Urgency score: {turn.running_urgency_score}."
        )

    return ChatResponse(
        session_id=UUID(session_id),
        timestamp=assistant_time,
        response_type=response_type,
        content=content,
    )


@router.get("/chats/{session_id}", response_model=HistoryResponse)
async def get_chats(session_id: UUID):
    try:
        chats = db.session_details(str(session_id))
    except RuntimeError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return HistoryResponse(session_id=session_id, chats=chats)
