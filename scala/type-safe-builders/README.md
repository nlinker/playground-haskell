# Typesafe builders in Scala

Kotlin has [typesafe bulders](https://kotlinlang.org/docs/reference/type-safe-builders.html)
pattern. One might think that it is unique feature unacheavable from
Java and Scala. Not sure about Java, but Scala is powerful enough to
replicate this pattern verbatim. This example shows this.

```scala
def result(args: Array[String]) =
    html {
        head {
            title {+"XML encoding with Scala"}
        }
        body {
            h1 {+"XML encoding with Scala"}
            p  {+"this format can be used as an alternative markup to XML"}

            // an element with attributes and text content
            a(href = "http://scala-lang.org") {+"Scala"}

            // mixed content
            p {
                +"This is some"
                b {+"mixed"}
                +"text. For more see the"
                a(href = "http://scala-lang.org") {+"Scala"}
                +"project"
            }
            p {+"some text"}

            // content generated by
            p {
                for (arg in args)
                    +arg
            }
        }
    }
```
