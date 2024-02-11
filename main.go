package main

import (
	"fmt"
)

func say(text string) {
	fmt.Printf(text)
}
func world() {
	say("Hello World1")
}

func indirect() {
}

func hello1() {
	world()
}

func world2() {
	say("Hello World2")
}
func hello2() {
	world2()
}

func main() {
	hello1()
    hello2()
}
