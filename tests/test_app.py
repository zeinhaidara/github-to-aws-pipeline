from app.app import app


def test_home_page():
    client = app.test_client()
    response = client.get("/")

    assert response.status_code == 200
    assert b"GitHub to AWS CI/CD" in response.data
