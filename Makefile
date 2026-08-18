.PHONY: project test icon

project:
	xcodegen generate

test:
	swift test

icon:
	python3 scripts/generate_icon.py
