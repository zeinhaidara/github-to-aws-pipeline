import os

from flask import Flask, render_template


app = Flask(__name__)


@app.get("/")
def home():
    return render_template("index.html")


if __name__ == "__main__":
    app.run(host=os.getenv("APP_HOST", "0.0.0.0"), port=8080)
