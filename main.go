package main

import (
	"fmt"
)

func say(word string) {
	fmt.Println(word)
}

func sayHello() {
	say("hello world")
}

func newWorld() {
    sayHello()
}

func main() {
	sayHello()
	sayHello()
}


