from services.report import apply_confirmed_symptoms, force_report


def test_force_report_normalizes_case_and_whitespace() -> None:
    state = {"questions_asked": 0, "total_urgency_score": 0}

    assert force_report(state, "  I AM   DONE ")
    assert force_report(state, "It's urgent")
    assert force_report(state, "its    urgent")


def test_server_urgency_only_counts_new_database_backed_symptoms() -> None:
    """A symptom already on record is not re-counted, whatever case it arrives in."""
    confirmed_symptoms = [
        {"name": "chest pain", "urgency_score": 95.0},
        {"name": "fainting", "urgency_score": 75.0},
    ]

    symptoms, score, breakdown = apply_confirmed_symptoms(
        ["Chest Pain"],
        95.0,
        confirmed_symptoms,
    )

    assert symptoms == ["Chest Pain", "fainting"]
    # urgency_score is an absolute 0-100 severity per symptom, so the worst one
    # stands rather than the two being added into a false emergency.
    assert score == 95.0
    assert breakdown == [75.0]


def test_a_worse_symptom_raises_the_score_a_milder_one_does_not_lower_it() -> None:
    _, raised, _ = apply_confirmed_symptoms(
        ["sore throat"], 30.0, [{"name": "chest pain", "urgency_score": 95.0}],
    )
    assert raised == 95.0

    _, held, _ = apply_confirmed_symptoms(
        ["chest pain"], 95.0, [{"name": "runny nose", "urgency_score": 15.0}],
    )
    assert held == 95.0


def test_server_urgency_stays_within_the_scale() -> None:
    symptoms, score, breakdown = apply_confirmed_symptoms(
        [],
        90.0,
        [{"name": "seizures", "urgency_score": 100.0}],
    )

    assert symptoms == ["seizures"]
    assert score == 100
    assert breakdown == [100.0]
