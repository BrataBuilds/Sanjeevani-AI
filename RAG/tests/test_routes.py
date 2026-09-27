"""Public RAG routes stay limited to the single chat protocol."""


def test_rag_exposes_chat_and_not_the_retired_triage_protocol() -> None:
    from main import app

    paths = {
        path
        for route in app.routes
        for path in (
            [route.path]
            if hasattr(route, "path")
            else [child.path for child in route.original_router.routes]
        )
    }
    assert "/chat" in paths
    assert "/triage" not in paths
