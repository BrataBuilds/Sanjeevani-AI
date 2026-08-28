from fastapi import APIRouter, HTTPException
from uuid import UUID
from services.report import report_exists
from schemas.triage import PreliminaryReport
from services.report import read_report as read_generated_report

router = APIRouter()
@router.get("/generate-report/{session_id}", response_model=PreliminaryReport)
async def read_report(session_id: UUID):
    report_session_id = str(session_id)
    if not report_exists(report_session_id):
        raise HTTPException(status_code=404, detail="Report not found")
    report = read_generated_report(report_session_id)
    if report is None:
        raise HTTPException(status_code=409, detail="Report not yet generated for this session")
    return report
