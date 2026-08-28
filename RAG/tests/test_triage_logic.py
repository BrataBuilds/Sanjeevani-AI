from services.report import apply_confirmed_symptoms, force_report


def test_force_report_normalizes_case_and_whitespace() -> None:
    state = {"questions_asked": 0, "total_urgency_score": 0}

    assert force_report(state, "  I AM   DONE ")
    assert force_report(state, "It's urgent")
    assert force_report(state, "its    urgent")


def test_server_urgency_only_adds_new_database_backed_symptoms() -> None:
    confirmed_symptoms = [
        {"name": "chest pain", "urgency_score": 45.0},
        {"name": "fainting", "urgency_score": 35.0},
    ]

    symptoms, score, breakdown = apply_confirmed_symptoms(
        ["Chest Pain"],
        45.0,
        confirmed_symptoms,
    )

    assert symptoms == ["Chest Pain", "fainting"]
    assert score == 80.0
    assert breakdown == [35.0]


def test_server_urgency_is_capped() -> None:
    symptoms, score, breakdown = apply_confirmed_symptoms(
        [],
        90.0,
        [{"name": "seizures", "urgency_score": 50.0}],
    )

    assert symptoms == ["seizures"]
    assert score == 100
    assert breakdown == [50.0]
