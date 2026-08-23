.PHONY: setup test print-test clean swift-test swift-build swift-run swift-app

setup:
	python3 -m venv .venv
	.venv/bin/pip install --quiet --upgrade pip
	.venv/bin/pip install --quiet -r requirements.txt pytest

test:
	.venv/bin/python -m pytest tests -v

print-test:
	.venv/bin/python -m epson_print.cli samples/test-page.pdf

swift-test:
	cd swift && swift test

swift-build:
	cd swift && swift build

swift-run:
	cd swift && swift run l3270 --help

swift-app:
	cd swift && swift build --product L3270App
	./swift/scripts/build-app.sh

clean:
	rm -rf .venv __pycache__ .pytest_cache swift/.build
	find . -name '*.pyc' -delete
