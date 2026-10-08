package main

import "golang.org/x/text/language"

func vulnerableDemo() {
	_, _, _ = language.ParseAcceptLanguage("en-US,en;q=0.9")
}
