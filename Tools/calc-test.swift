// Standalone test for the calculator engine — compiles the *real* Foundation-only engine sources (no copy to sync): swiftc Tinycast/Core/Calculator/*.swift Tools/calc-test.swift -o /tmp/calc-test && /tmp/calc-test

import Foundation

@main
@MainActor
struct CalcTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        if CommandLine.arguments.contains("--bench") {
            runBenchmark()
            return
        }

        // Arithmetic & precedence
        expectDisplay("=2+2", "4")
        expectDisplay("=5*7", "35")
        expectDisplay("=100/4", "25")
        expectDisplay("=2^10", "1,024")
        expectDisplay("=2^3^2", "512")  // right-associative
        expectDisplay("=2**2", "4")  // "**" is an alias for "^" (Python/JS/shell spelling)
        expectDisplay("=2**10", "1,024")
        expectDisplay("=2**3**2", "512")  // right-associative, same as "^"
        expectDisplay("=(5+2)*3", "21")
        expectDisplay("=5!", "120")
        expectDisplay("=3!!", "720")  // (3!)! — chained postfix
        expectDisplay("=-5+3", "-2")
        expectDisplay("=-2^2", "-4")  // unary minus binds looser than ^
        expectDisplay("=10/4", "2.5")
        expectDisplay("=1/3", "0.3333333333")
        expectDisplay("=2.5 * 4", "10")
        expectDisplay("=1,000 + 234", "1,234")  // grouping commas accepted in input

        // Compact thousands suffix — attached `k` is a number suffix; spaced `k` remains Kelvin
        expectDisplay("=10k", "10,000")
        expectCopy("=10k", "10000")
        expectDisplay("=2.5K", "2,500")
        expectDisplay("=10k + 500", "10,500")
        expectDisplay("=10k * 2", "20,000")
        expectBadges("=10k", source: "Expression", target: "Result")

        // Scientific notation input
        expectDisplay("=1e6 + 1", "1,000,001")
        expectDisplay("=1.5e-3 * 2", "0.003")
        expectDisplay("=2.5e8 / 2", "125,000,000")
        expectDisplay("=1E6 + 1", "1,000,001")  // uppercase E
        expectDisplay("=1e6", "1,000,000")  // a lone shorthand literal cards like "10k"
        expectNil("10em")  // partial "e" isn't an exponent, so the ident scanner still gets it
        expectDisplay("=1e3k + 1", "1,000,001")  // exponent then compact suffix, both applied

        // Exact up to 2^53, past the old 1e15 cutoff — truncating these lost real digits on copy
        expectDisplay("=2^49", "562,949,953,421,312")
        expectDisplay("=2^50", "1,125,899,906,842,624")
        expectCopy("=2^50", "1125899906842624")
        expectDisplay("=999999999999999 + 1", "1,000,000,000,000,000")  // exactly the old cutoff
        // Beyond 2^53 the precision is genuinely gone, so exponent form is the honest answer
        expectDisplay("=123456789 * 123456789", "1.524157875e+16")

        // Functions
        expectDisplay("=sqrt(64)", "8")
        expectDisplay("=sqrt 64", "8")
        expectDisplay("=sqrt 64 + 36", "44")  // bare arg is one operand: sqrt(64) + 36
        expectDisplay("=log(1000)", "3")
        expectDisplay("=ln(e)", "1")
        expectDisplay("=sin(30deg)", "0.5")
        expectDisplay("=cos(60deg)", "0.5")
        expectDisplay("=tan(45deg)", "1")
        expectDisplay("=sin(pi/2)", "1")
        expectDisplay("=abs(-4)", "4")
        expectDisplay("=floor(2.7)", "2")
        expectDisplay("=ceil(2.1)", "3")
        expectDisplay("=round(2.5)", "3")
        expectDisplay("=SQRT(64)", "8")  // case-insensitive

        // Constants
        expectDisplay("=2*pi", "6.283185307")
        expectDisplay("=π*2", "6.283185307")
        expectDisplay("=e^2", "7.389056099")

        // Implicit multiplication
        expectDisplay("=4(2+3)", "20")
        expectDisplay("=(2+3)(2+3)", "25")
        expectDisplay("=2pi", "6.283185307")
        expectDisplay("=2π", "6.283185307")
        expectDisplay("=2sqrt(9)", "6")
        expectDisplay("=2(3+1)+1", "9")  // implicit "*" binds like explicit "*", not looser
        expectDisplay("=10π ^e", "224.5915772")  // and looser than "^"
        // Units are never mistaken for a constant/function, so this stays untouched
        expectDisplay("=10km to mi", "6.213711922 mi")
        // Juxtaposition against a bracket carries the unit through, matching explicit "*"
        expectDisplay("=2(3)kg", "6 kg")
        expectDisplay("=2*(3)kg", "6 kg")

        // Scientific notation — only when the exponent hugs the mantissa
        expectDisplay("=1e5", "100,000")
        expectDisplay("=2e10", "20,000,000,000")
        expectDisplay("=1E5", "100,000")
        expectDisplay("=1.5e3", "1,500")
        expectDisplay("=3e+2", "300")
        expectCopy("=1e-5", "1e-05")
        expectDisplay("=2e10/2", "10,000,000,000")
        expectDisplay("=1e5 to hex", "0x186A0")
        expectDisplay("=5e-3km", "0.003106855961 mi")
        expectDisplay("=2e", "5.436563657")  // no digits after "e" — still 2 × Euler's e
        expectDisplay("=1 e", "2.718281828")  // detached — never an exponent
        expectNil("1e400")  // overflows to infinity, so not calculator input
        expectNil("1e5e5")

        // Percent
        expectDisplay("=20% of 450", "90")
        expectDisplay("=450 + 20%", "540")
        expectDisplay("=450 - 15%", "382.5")
        expectDisplay("=20%", "0.2")

        // Modulo — spelled out, so it never competes with the percent cases above
        expectDisplay("=10 mod 3", "1")
        expectDisplay("=17 mod 5", "2")
        expectDisplay("=10k mod 3", "1")
        expectDisplay("=-10 mod 3", "-1")  // fmod semantics: the sign follows the dividend
        expectDisplay("=2 + 10 mod 3", "3")  // same precedence as * and /, binds tighter than +
        expectNil("10 mod 0")
        expectNil("10 % 3")  // "%" stays percent, whatever follows it
        expectDisplay("=450 + 20% - 5", "535")

        // New scalar functions (inverse trig, hyperbolic, etc.)
        expectDisplay("=asin(0.5)", "0.5235987756")
        expectDisplay("=asin(0)", "0")
        expectDisplay("=asin(1)", "1.570796327")
        expectDisplay("=asin(-1)", "-1.570796327")
        expectNil("asin(2)")
        expectNil("asin(-2)")
        expectDisplay("=acos(0.5)", "1.047197551")
        expectDisplay("=acos(1)", "0")
        expectDisplay("=acos(-1)", "3.141592654")
        expectDisplay("=atan(1)", "0.7853981634")
        expectDisplay("=atan(0)", "0")
        // atan2: all four quadrants
        expectDisplay("=atan2(1, 1)", "0.7853981634")
        expectDisplay("=atan2(1, -1)", "2.35619449")
        expectDisplay("=atan2(-1, -1)", "-2.35619449")
        expectDisplay("=atan2(-1, 1)", "-0.7853981634")
        expectDisplay("=atan2(0, -1)", "3.141592654")
        expectDisplay("=atan2(1, 0)", "1.570796327")
        expectDisplay("=sinh(0)", "0")
        expectDisplay("=cosh(0)", "1")
        expectDisplay("=tanh(0)", "0")
        expectDisplay("=sinh(1)", "1.175201194")
        expectDisplay("=cosh(1)", "1.543080635")
        expectDisplay("=log2(8)", "3")
        expectDisplay("=log2(1)", "0")
        expectDisplay("=log2(0.5)", "-1")
        expectNil("log2(-1)")
        expectDisplay("=exp(1)", "2.718281828")
        expectDisplay("=exp(0)", "1")
        expectDisplay("=exp2(3)", "8")
        expectDisplay("=exp2(0)", "1")
        expectDisplay("=exp2(-1)", "0.5")
        expectDisplay("=sign(5)", "1")
        expectDisplay("=sign(-3)", "-1")
        expectDisplay("=sign(0)", "0")
        expectDisplay("=sign(-0.001)", "-1")
        expectDisplay("=fract(2.7)", "0.7")
        expectDisplay("=fract(-2.3)", "0.7")
        expectDisplay("=fract(5)", "0")
        expectDisplay("=fract(-5)", "0")
        expectDisplay("=trunc(2.7)", "2")
        expectDisplay("=trunc(-2.7)", "-2")
        expectDisplay("=trunc(0)", "0")
        expectDisplay("=deg(pi)", "180")
        expectDisplay("=deg(pi/2)", "90")
        expectDisplay("=rad(180)", "3.141592654")
        expectDisplay("=rad(90)", "1.570796327")
        expectDisplay("=saturate(0.5)", "0.5")
        expectDisplay("=saturate(2)", "1")
        expectDisplay("=saturate(-1)", "0")
        expectDisplay("=saturate(0)", "0")
        expectDisplay("=saturate(1)", "1")

        // Binary scalar functions
        expectDisplay("=step(0.5, 1)", "0")
        expectDisplay("=step(2, 1)", "1")
        expectDisplay("=step(0, 0)", "1")
        expectDisplay("=step(-1, -0.5)", "0")
        expectDisplay("=hypot(3, 4)", "5")
        expectDisplay("=hypot(0, 0)", "0")
        expectDisplay("=hypot(-3, 4)", "5")

        // Ternary scalar functions
        expectDisplay("=clamp(0.5, 0, 1)", "0.5")
        expectDisplay("=clamp(2, 0, 1)", "1")
        expectDisplay("=clamp(-1, 0, 1)", "0")
        expectDisplay("=lerp(0, 10, 0.5)", "5")
        expectDisplay("=lerp(0, 10, 0)", "0")
        expectDisplay("=lerp(0, 10, 1)", "10")
        expectDisplay("=lerp(0, 10, 2)", "20")
        expectDisplay("=smoothstep(0, 1, 0.5)", "0.5")
        expectDisplay("=smoothstep(0, 1, 0.2)", "0.104")
        expectDisplay("=smoothstep(0, 1, 0)", "0")
        expectDisplay("=smoothstep(0, 1, 1)", "1")
        expectDisplay("=smoothstep(0, 1, -0.5)", "0")
        expectDisplay("=smoothstep(0, 1, 1.5)", "1")
        expectDisplay("=inverseLerp(0, 10, 5)", "0.5")
        expectDisplay("=inverseLerp(0, 10, 0)", "0")
        expectDisplay("=inverseLerp(0, 10, 10)", "1")

        // New constants
        expectDisplay("=tau", "6.283185307")
        expectDisplay("=tau/2", "3.141592654")
        expectDisplay("=tau/pi", "2")
        expectDisplay("=phi", "1.618033989")
        expectDisplay("=φ", "1.618033989")
        expectDisplay("=phi^2", "2.618033989")

        // Vector literals — basic
        expectVector("=(1, 2)", "(1, 2)")
        expectVector("=(1, 2, 3)", "(1, 2, 3)")
        expectVector("=(1, 2, 3, 4)", "(1, 2, 3, 4)")
        expectNil("(1, 2, 3, 4, 5)")
        // Vector literals with expressions
        expectVector("=(1+1, 2*3, 4/2)", "(2, 6, 2)")
        expectVector("=(-1, -2, -3)", "(-1, -2, -3)")
        expectVector("=(sin(30deg), cos(60deg), 0)", "(0.5, 0.5, 0)")

        // Vector constructors
        expectVector("=vec2(1, 2)", "(1, 2)")
        expectVector("=vec3(1, 2, 3)", "(1, 2, 3)")
        expectVector("=vec4(1, 2, 3, 4)", "(1, 2, 3, 4)")
        expectDisplay("=(1)", "1")    // single element in parens is a scalar

        // Vector-scalar arithmetic
        expectVector("=2 * (1, 2, 3)", "(2, 4, 6)")
        expectVector("=(1, 2, 3) * 2", "(2, 4, 6)")
        expectVector("=(2, 4, 6) / 2", "(1, 2, 3)")
        expectVector("=(1, 2, 3) + (4, 5, 6)", "(5, 7, 9)")
        expectVector("=(4, 5, 6) - (1, 2, 3)", "(3, 3, 3)")
        expectVector("=-(1, 2, 3)", "(-1, -2, -3)")
        expectVector("=(1, 2) + 10", "(11, 12)")
        expectVector("=10 + (1, 2)", "(11, 12)")
        expectVector("=(5, 10) - 3", "(2, 7)")
        expectVector("=10 / (2, 5)", "(5, 2)")
        expectNil("(1, 2) + (3, 4, 5)")
        expectNil("(1, 2, 3) - (4, 5)")
        expectNil("(1, 2) * (3, 4, 5)")
        // Element-wise vector product (Hadamard)
        expectVector("=(1, 2, 3) * (4, 5, 6)", "(4, 10, 18)")
        expectVector("=(2, 3, 4) / (1, 2, 2)", "(2, 1.5, 2)")

        // Vector functions — length
        expectDisplay("=length(1, 2, 3)", "3.741657387")
        expectDisplay("=len(3, 4)", "5")
        expectDisplay("=length(0, 0, 0)", "0")
        expectDisplay("=length(1, 0, 0)", "1")
        expectDisplay("=length(vec3(2, 3, 6))", "7")

        // Vector functions — dot
        expectDisplay("=dot((1, 2, 3), (4, 5, 6))", "32")
        expectDisplay("=dot((1, 0), (0, 1))", "0")
        expectDisplay("=dot((2, 0), (3, 0))", "6")
        expectDisplay("=dot((1, 2, 3), (1, 2, 3))", "14")
        expectNil("dot((1, 2), (3, 4, 5))")

        // Vector functions — cross
        expectVector("=cross((1, 0, 0), (0, 1, 0))", "(0, 0, 1)")
        expectVector("=cross((0, 1, 0), (1, 0, 0))", "(0, 0, -1)")
        expectVector("=cross((1, 0, 0), (1, 0, 0))", "(0, 0, 0)")
        expectVector("=cross((2, 0, 0), (0, 3, 0))", "(0, 0, 6)")
        expectNil("cross((1, 2), (3, 4))")
        expectNil("cross((1, 2, 3, 4), (5, 6, 7, 8))")

        // Vector functions — normalize
        expectVector("=normalize(3, 4)", "(0.6, 0.8)")
        expectVector("=norm(1, 0, 0)", "(1, 0, 0)")
        expectDisplay("=length(normalize(1, 2, 3))", "1")
        expectNil("normalize(0, 0)")
        expectNil("normalize(0, 0, 0)")

        // Vector expressions combining functions
        expectVector("=(1, 2, 3) + 2 * (0, 1, 0)", "(1, 4, 3)")
        expectDisplay("=dot(normalize(1, 2), normalize(2, 4))", "1")
        expectVector("=normalize(cross((1,0,0), (0,1,0)))", "(0, 0, 1)")

        // Vector copy text
        expectVectorCopy("=(1, 2, 3)", "(1, 2, 3)")
        expectVectorCopy("=(1.5, 2.5, 3.5)", "(1.5, 2.5, 3.5)")
        expectVectorCopy("=2 * (1.5, 2, 3)", "(3, 4, 6)")

        // Commas inside numbers are still grouping separators, not vector delimiters
        expectDisplay("=1,234 + 1", "1,235")
        expectDisplay("=10km to mi", "6.213711922 mi")
        expectDisplay("=10 km in miles", "6.213711922 mi")
        expectDisplay("=5ft in cm", "152.4 cm")
        expectDisplay("=1 m to ft", "3.280839895 ft")
        expectDisplay("=10 cm in in", "3.937007874 in")
        expectDisplay("=10 in in cm", "25.4 cm")  // first "in" is the unit, second the connector
        expectDisplay("=16 oz to lb", "1 lb")
        expectDisplay("=2.2 lbs to kg", "0.997903214 kg")
        expectDisplay("=100 C to F", "212 °F")
        expectDisplay("=32F to C", "0 °C")
        expectDisplay("=273.15K to C", "0 °C")  // attached Kelvin remains valid in a conversion
        expectDisplay("=273.15 K to C", "0 °C")
        expectDisplay("=10 k to c", "-263.15 °C")
        expectDisplay("=0 F to C", "-17.77777778 °C")
        expectDisplay("=300 K to C", "26.85 °C")
        expectDisplay("=90min to hr", "1.5 hr")
        expectDisplay("=2hr to min", "120 min")
        expectDisplay("=1day to sec", "86,400 s")
        expectDisplay("=1 week to hr", "168 hr")
        expectDisplay("=2 acre to m2", "8,093.712845 m²")
        expectDisplay("=1 m² to ft²", "10.76391042 ft²")
        expectDisplay("=2L -> mL", "2,000 mL")
        expectDisplay("=1 cup to tbsp", "16 tbsp")
        expectDisplay("=1 gal to L", "3.785411784 L")
        expectDisplay("=1 GiB to MB", "1,073.741824 MB")
        expectDisplay("=1 GB to MiB", "953.6743164 MiB")
        expectDisplay("=8 bit to byte", "1 B")
        expectDisplay("=2*5 km to mi", "6.213711922 mi")  // expression on the left side

        // Number bases
        expectDisplay("=255 to hex", "0xFF")
        expectDisplay("=255 to binary", "0b11111111")
        expectDisplay("=0xff to decimal", "255")
        expectDisplay("=0b1010 to decimal", "10")
        expectDisplay("=255 to octal", "0o377")
        expectDisplay("=0xff", "255")  // bare radix literal echoes decimal

        // Friendly category errors
        expectError("=10kg to sec", "Cannot convert Weight to Time.")
        expectError("=100 mL to km", "Cannot convert Volume to Length.")
        expectError("=1 GB to hr", "Cannot convert Digital Storage to Time.")

        // Non-calculator input → no card
        expectNil("safari")
        expectNil("1password")
        expectNil("45")
        expectNil("3.14")
        expectDisplay("=pi", "3.141592654")
        expectDisplay("=e", "2.718281828")
        expectNil("10km to")  // half-typed conversion
        expectNil("10 to mi")
        expectDisplay("=45+", "45")  // safe trailing operators keep the last complete result
        expectNil("sqrt()")
        expectNil("2.5!")  // factorial needs an integer
        expectNil("")

        // Formatting: display grouped, copyText plain
        expectDisplay("=1234567*1", "1,234,567")
        expectCopy("=1234567*1", "1234567")
        expectCopy("=10km to mi", "6.213711922 mi")
        expectDisplay("=-1234.5-0.25", "-1,234.75")

        // Card expression echo
        expectExpression("=3*3", "3×3")
        expectExpression("=10km to mi", "10 km")

        // Badges on explicit conversions
        expectBadges("=10km to mi", source: "Kilometers", target: "Miles")
        expectBadges("=100 C to F", source: "Celsius", target: "Fahrenheit")

        // Bare-unit auto-conversion (no connector)
        expectDisplay("=1m", "3 feet 3.37007874 inches")
        expectExpression("=1m", "1 m")
        expectBadges("=1m", source: "Meters", target: "Feet")
        expectDisplay("=1hr", "60 min")
        expectBadges("=1hr", source: "Hours", target: "Minutes")
        expectDisplay("=5ft", "1.524 m")
        expectDisplay("=100g", "3.527396195 oz")
        expectDisplay("=2*3 kg", "6 kg")  // an operator keeps the answer in the units written
        expectDisplay("=20 celsius", "68 °F")
        expectDisplay("=50cm", "19.68503937 in")
        // Ambiguous single-letter aliases stay app searches, not bare temperatures
        expectNil("5 k")
        expectNil("100 c")
        expectNil("32f")

        // Unit expressions — addition/subtraction converts the RHS and keeps the leftmost unit
        expectDisplay("=10kg + 5kg", "15 kg")
        expectCopy("=10kg + 5kg", "15 kg")
        expectExpression("=10kg + 5kg", "10 kg + 5 kg")
        // Signs, parens and postfix % hug their operand instead of floating as separate words
        expectExpression("=10kg * 3%", "10 kg × 3%")
        expectExpression("=(10kg + 5kg) * 3%", "(10 kg + 5 kg) × 3%")
        expectExpression("=-5kg + 2kg", "-5 kg + 2 kg")
        expectExpression("=5 feet 3 inches", "5 ft 3 in")
        expectBadges("=10kg + 5kg", source: "Expression", target: "Kilograms")
        expectDisplay("=10kg + 10g", "10,010 g")  // issue #64, answered in the last unit typed
        expectDisplay("=10kg + 500g", "10,500 g")
        expectDisplay("=500g + 1kg", "1.5 kg")
        expectCopy("=500g + 1kg", "1.5 kg")
        expectDisplay("=10lb + 5kg", "9.5359237 kg")
        expectDisplay("=1m + 50cm", "150 cm")
        expectDisplay("=2hr + 30min", "150 min")
        expectDisplay("=1GiB + 512MiB", "1,536 MiB")
        expectDisplay("=1L - 250mL", "750 mL")
        expectDisplay("=-5kg + 2kg", "-3 kg")
        expectDisplay("=-(2kg + 500g)", "-2,500 g")
        expectDisplay("=10 pounds + 5 pounds", "15 lb")  // unit wins the currency collision
        expectDisplay("=1m² + 10ft²", "20.76391042 ft²")
        expectDisplay("=1L + 1cup", "5.226752838 cup")
        expectDisplay("=1GB + 1GiB", "1.931322575 GiB")
        expectDisplay("=90deg + 1rad", "2.570796327 rad")
        expectDisplay("=60mph + 10kmh", "106.56064 km/h")
        expectDisplay("=1bar + 10psi", "24.50377377 psi")
        expectDisplay("=1Gbps + 500Mbps", "1,500 Mbps")

        // Unit-expression precedence, parentheses, scalar operations, and cancellation
        expectDisplay("=10kg + 2 * 5kg", "20 kg")
        expectDisplay("=(10kg + 5kg) * 2", "30 kg")
        expectDisplay("=2 * (3kg + 500g)", "7,000 g")
        expectDisplay("=20kg / 2 + 3kg", "13 kg")
        expectDisplay("=20kg / (2 + 3)", "4 kg")
        expectDisplay("=5kg * 3", "15 kg")
        expectDisplay("=10kg / 4", "2.5 kg")
        expectDisplay("=5kg / 2kg", "2.5")
        expectBadges("=5kg / 2kg", source: "Expression", target: "Result")
        expectDisplay("=5kg / 500g", "10")
        expectDisplay("=1kg / 3", "0.3333333333 kg")
        expectDisplay("=10kg * (2 + 3)", "50 kg")
        expectDisplay("=10kg / (2 * 5)", "1 kg")
        expectDisplay("=(10kg * 3) / 5kg", "6")
        expectDisplay("=10kg / (5kg / 2)", "4")
        expectDisplay("=(2kg + 500g) * 4", "10,000 g")
        expectDisplay("=(20kg - 5kg) / 3", "5 kg")

        // Percentages carry through quantity arithmetic
        expectDisplay("=10kg + 20%", "12 kg")
        expectDisplay("=10kg - 20%", "8 kg")
        expectDisplay("=10kg * 20%", "2 kg")
        expectDisplay("=10kg * 3%", "0.3 kg")
        expectDisplay("=3% * 10kg", "0.3 kg")
        expectDisplay("=10kg * 0%", "0 kg")
        expectDisplay("=10kg * -3%", "-0.3 kg")
        expectDisplay("=10kg / 25%", "40 kg")
        expectDisplay("=10kg / 200%", "5 kg")
        expectDisplay("=10kg * 3% + 1kg", "1.3 kg")
        expectDisplay("=(10kg + 5kg) * 3%", "0.45 kg")
        expectDisplay("=10kg * 3% to g", "300 g")
        expectCopy("=10kg * 3% to g", "300 g")
        expectDisplay("=20% of (10kg + 5kg)", "3 kg")
        expectDisplay("=3% of 10kg", "0.3 kg")
        expectNil("10kg / 0%")
        expectDisplay("=19m + 47%", "27.93 m")  // documented Raycast behavior

        // Incomplete expressions retain the last complete, actionable result
        expectDisplay("=10 +", "10")
        expectDisplay("=10 -", "10")
        expectDisplay("=10 *", "10")
        expectDisplay("=10 /", "10")
        expectDisplay("=10 ^", "10")
        expectDisplay("=10k +", "10,000")
        expectCopy("=10k +", "10000")
        expectDisplay("=10kg *", "10 kg")
        expectDisplay("=10kg + 500g +", "10,500 g")
        expectDisplay("=(10kg + 500g) *", "10,500 g")
        expectDisplay("=10kg * 3% +", "0.3 kg")
        expectDisplay("=20% of 450 +", "90")
        expectBadges("=10 +", source: "Expression", target: "Result")
        expectBadges("=10kg *", source: "Expression", target: "Kilograms")
        expectNil("+")
        expectNil("10 + nonsense")
        expectNil("10 + (")
        expectNil("10 of")  // a stray English word is a search, not a partial expression

        // A partial after a conversion echoes the typed text, and keeps the source radix / units
        expectExpression("=10km to mi *", "10km to mi ×")
        expectDisplay("=10km to mi *", "6.213711922 mi")
        expectExpression("=255 to hex +", "255 to hex +")
        expectBadges("=0xff -", source: "Hexadecimal", target: "Decimal")
        expectDisplay("=0xff -", "255")

        // A conversion suffix applies to the complete unit expression
        expectDisplay("=(1kg + 500g) to lb", "3.306933933 lb")
        expectDisplay("=10kg + 500g to lb", "23.14853753 lb")
        expectDisplay("=(10lb + 5kg) to kg", "9.5359237 kg")
        expectDisplay("=(1m + 50cm) to ft", "4.921259843 ft")
        expectBadges("=(1kg + 500g) to lb", source: "Expression", target: "Pounds")
        expectError("=(1kg + 500g) to m", "Cannot convert Weight to Length.")

        // Adjacent compatible quantities are additive, matching common composite-unit notation.
        // Composite reads as one quantity in its leading unit; an explicit operator answers in the last.
        expectDisplay("=5 feet 3 inches to cm", "160.02 cm")
        expectDisplay("=5 feet 3 inches", "5.25 ft")
        expectDisplay("=1hr 30min", "1.5 hr")
        expectDisplay("=5feet + 1m", "2.524 m")
        expectBadges("=5feet + 1m", source: "Expression", target: "Meters")
        expectDisplay("=1kg + 500g + 2lb", "5.306933933 lb")  // chained: the last unit wins
        expectDisplay("=2 * 5kg", "10 kg")
        expectDisplay("=3 * 2m", "6 m")

        // Affine temperatures only combine in the same unit; mixed absolute scales are ambiguous
        expectDisplay("=20 celsius + 10 celsius", "30 °C")
        expectDisplay("=68 fahrenheit - 32 fahrenheit", "36 °F")
        expectError(
            "=20 celsius + 50 fahrenheit",
            "Cannot combine temperatures with different units.")

        // Clear dimensional mistakes are errors; incomplete or non-finite input stays silent
        expectError("=1kg + 1m", "Cannot add Weight and Length.")
        expectError("=1kg + 1hr", "Cannot add Weight and Time.")
        // A bare number written against a quantity takes its unit
        expectDisplay("=1kg + 1", "2 kg")
        expectDisplay("=10kg + 5", "15 kg")
        expectDisplay("=5kg+5", "10 kg")
        expectDisplay("=5 + 10kg", "15 kg")
        expectDisplay("=$10 + 5", "15.00 USD")
        expectBadges("=5kg+5", source: "Expression", target: "Kilograms")
        expectDisplay("=10kg + -20%", "9.8 kg")  // unary minus drops percent, as in `450 + -20%`
        // Adjacency is different: there a bare number is a unit still being typed, so it stays silent
        expectNil("1hr 30")  // mid-way through "1hr 30min"
        expectNil("5 feet 3")  // mid-way through "5 feet 3 inches"
        expectError(
            "=1kg * 1m",
            "Multiplication of two unit values is not supported.")
        expectError("=1 / 1kg", "Division by a unit value is not supported.")
        expectNil("(2m)^2")
        expectNil("sqrt(4kg)")
        expectNil("1kg!")
        expectDisplay("=10kg +", "10 kg")
        expectCopy("=10kg +", "10 kg")
        expectExpression("=10kg +", "10 kg +")
        expectBadges("=10kg +", source: "Expression", target: "Kilograms")
        expectNil("10kg + nonsense")
        expectNil("10unknown + 5unknown")
        expectNil("10kg / 0")
        expectDisplay("=1234kg + 1kg", "1,235 kg")
        expectCopy("=1234kg + 1kg", "1235 kg")

        // Date/time — evaluated against a fixed clock: Fri 2026-07-24 00:18 UTC
        expectDisplayAt("=hrs till 9am", "8.7 hours")
        expectBadgesAt("=hrs till 9am", source: "12:18 AM", target: "9:00 AM")
        expectDisplayAt("=hrs till july", "8,207.7 hours")
        expectBadgesAt("=hrs till july", source: "12:18 AM", target: "12:00 AM")
        expectDisplayAt("=days till 9april", "259 days")
        expectBadgesAt(
            "=days till 9april", source: "Friday, 24 July", target: "Friday, 9 April, 2027")
        expectDisplayAt("=days till july", "342 days")
        expectBadgesAt(
            "=days till july", source: "Friday, 24 July", target: "Thursday, 1 July, 2027")
        expectDisplayAt("=days until tomorrow", "1 day")
        expectDisplayAt("=weeks till 9april", "37 weeks")  // 259 / 7
        expectDisplayAt("=today + 3 weeks", "Friday, 14 August")
        expectDisplayAt("=now + 90 min", "Friday, 24 July at 1:48 AM")
        expectDisplayAt("=jul 4 - today", "345 days")
        expectBadgesAt("=jul 4 - today", source: "Sunday, 4 July, 2027", target: "Friday, 24 July")
        // Arithmetic with spaced operators must still be plain math, not date math
        expectDisplayAt("=10 - 3", "7")
        expectDisplayAt("=450 + 20%", "540")
        // Letter-free `m/d - m/d` is fraction math, not a date difference (both operands are valid arithmetic)
        expectDisplayAt("=5/2 - 1/2", "2")
        expectDisplayAt("=3/4 - 1/4", "0.5")
        expectDisplayAt("=1/2 - 1/4", "0.25")
        // A slash date still reads as a date when the other side names a keyword
        expectDisplayAt("=9/4 - today", "42 days")
        expectDisplayAt("=today - 9/4", "-42 days")
        // Bare date/unit words alone are app searches, not cards
        expectNilAt("today")
        expectNilAt("july")
        expectNilAt("tomorrow")

        // Angle units (deg is a real unit now, not just a trig postfix)
        expectDisplay("=1 deg", "0.01745329252 rad")
        expectExpression("=1 deg", "1 deg")
        expectBadges("=1 deg", source: "Degrees", target: "Radians")
        expectDisplay("=90 deg to rad", "1.570796327 rad")
        expectDisplay("=1 rad to deg", "57.29577951 deg")
        expectDisplay("=1 turn to deg", "360 deg")
        expectDisplay("=200 grad to deg", "180 deg")
        expectDisplay("=sin(30deg)", "0.5")  // trig postfix still works inside parens

        // Implied quantity of 1 for number-less conversions
        expectDisplay("=day to s", "86,400 s")
        expectDisplay("=deg to rad", "0.01745329252 rad")
        expectDisplay("=m to ft", "3.280839895 ft")

        // `unit unit` shorthand → 1 of the first in the second
        expectDisplay("=day s", "86,400 s")
        expectBadges("=day s", source: "Days", target: "Seconds")
        expectDisplay("=days s", "86,400 s")
        expectDisplay("=hr min", "60 min")
        expectNil("m s")  // different categories → no card, no error

        // Extra unit categories: speed / pressure / data rate
        expectDisplay("=100 kmh to mph", "62.13711922 mph")
        expectDisplay("=60 mph to kmh", "96.56064 km/h")
        expectDisplay("=100 mbps to kbps", "100,000 Kbps")
        expectBadges("=100 kmh to mph", source: "Kilometers per Hour", target: "Miles per Hour")

        // Bare-unit auto-conversion coverage gaps: bar/psi/atm/Mbps/Gbps/Kbps had it, their
        // neighbors didn't — same category, same treatment.
        expectDisplay("=5 mbar", "0.07251886887 psi")
        expectDisplay("=5 kPa", "0.7251886887 psi")
        expectDisplay("=5 hPa", "0.07251886887 psi")
        expectDisplay("=5 mmHg", "0.0966838873 psi")
        expectDisplay("=5 Torr", "0.09668387352 psi")
        expectDisplay("=100 bps", "0.1 Kbps")
        expectDisplay("=1 Tbps", "1,000 Gbps")

        // Base conversion accepts an expression on the value side, like unit conversion already does
        expectDisplay("=2*128 to hex", "0x100")
        expectDisplay("=10*5 to hex", "0x32")

        // Percentage phrasings
        expectDisplay("=20% off 500", "400")
        expectDisplay("=50 as % of 200", "25%")

        // Badges on paths that previously had none
        expectBadges("=255 to hex", source: "Decimal", target: "Hexadecimal")
        expectBadges("=0xff to decimal", source: "Hexadecimal", target: "Decimal")
        expectBadges("=3*3", source: "Expression", target: "Result")
        expectBadges("=20% off 500", source: "Expression", target: "Result")

        // days since — past elapsed, against the fixed clock (Fri 2026-07-24)
        expectDisplayAt("=days since 9jul", "15 days")
        expectBadgesAt("=days since 9jul", source: "Thursday, 9 July", target: "Friday, 24 July")
        expectDisplayAt("=weeks since 3jul", "3 weeks")
        expectDisplayAt("=days since yesterday", "1 day")
        // Date ± duration now carries the resolved start as a source badge
        expectBadgesAt("=today + 3 weeks", source: "Friday, 24 July", target: "Result")

        // Currency — against the fixed `fx` table below (1 USD = 0.92 EUR = 0.79 GBP = 157 JPY)
        expectDisplay("=1 euro to dollars", "1.09 USD")
        expectExpression("=1 euro to dollars", "1 EUR")
        expectBadges("=1 euro to dollars", source: "Euro", target: "US Dollar")
        expectDisplay("=50 GBP in euros", "58.23 EUR")
        expectDisplay("=100 dollars to yen", "15,700.00 JPY")
        expectDisplay("=100 usd -> eur", "92.00 EUR")
        expectDisplay("=2*50 usd to eur", "92.00 EUR")  // expression on the value side
        expectDisplay("=eur to usd", "1.09 USD")  // implied amount of 1
        expectCopy("=100 dollars to yen", "15700.00 JPY")
        // Currency signs, prefixed and suffixed
        expectDisplay("=€20 to GBP", "17.17 GBP")
        expectDisplay("=20€ to GBP", "17.17 GBP")
        expectDisplay("=USD1K to EUR", "920.00 EUR")
        expectDisplay("=1kUSD to EUR", "920.00 EUR")
        expectDisplay("=£50 in dollars", "63.29 USD")
        expectDisplay("=$100 to yen", "15,700.00 JPY")
        // Sub-cent cross-rates widen instead of collapsing to 0.00
        expectDisplay("=1 jpy to usd", "0.006369 USD")
        // …and stay in plain notation past 1e-5, where "%g" would flip to "5.539e-05"
        expectDisplay("=1 idr to usd", "0.00005539 USD")
        expectCopy("=1 idr to usd", "0.00005539 USD")
        // Currency never steals a query the unit table can answer
        expectDisplay("=10 pounds to kilograms", "4.5359237 kg")
        expectDisplay("=10 pounds", "4.5359237 kg")
        expectDisplay("=10 pounds to euros", "11.65 EUR")
        expectBadges("=10 pounds to euros", source: "British Pound", target: "Euro")
        // Currency ↔ unit is a friendly category error, like Weight ↔ Time
        expectError("=10 usd to kg", "Cannot convert Currency to Weight.")
        expectError("=10 kg to usd", "Cannot convert Weight to Currency.")
        // A known currency the snapshot doesn't quote, and no snapshot at all
        expectError("=5 usd to npr", "No exchange rate for NPR.")
        expectErrorWithoutRates(
            "=1 eur to usd", "Exchange rates unavailable — check your connection.")
        expectNil("10 usd to nonsense")
        expectNil("usd")  // a lone code is still an app search
        expectNil("btc")  // crypto isn't in the table — Frankfurter is central-bank fiat only
        // The table is generated from the feed's own currency list, so codes nobody hand-typed still
        // resolve — reaching "no rate" (not "no card") is what proves recognition.
        expectError("=5 usd to zmw", "No exchange rate for ZMW.")
        expectError("=5 usd to afn", "No exchange rate for AFN.")
        check(
            "CurrencyData sizes", expected: "true",
            got:
                "\(CurrencyData.all.count >= 120 && CurrencyData.signs.count >= 20 && CurrencyData.aliases.count >= 100)"
        )
        // Badges come from CLDR's label, which is shorter than the registry name where it matters
        expectBadges("=1 chf to usd", source: "Swiss Franc", target: "US Dollar")
        expectBadges("=1 aed to usd", source: "UAE Dirham", target: "US Dollar")
        // Nouns only one currency claims are generated — nobody hand-typed these
        expectError("=1 zloty to usd", "No exchange rate for PLN.")
        expectError("=1 forint to usd", "No exchange rate for HUF.")
        expectError("=1 taka to usd", "No exchange rate for BDT.")
        expectError("=1 rand to usd", "No exchange rate for ZAR.")
        expectDisplay("=1 euro to dollars", "1.09 USD")
        // Accented nouns resolve with or without the accent
        expectError("=1 krónur to usd", "No exchange rate for ISK.")
        expectError("=1 kronur to usd", "No exchange rate for ISK.")
        // Nouns several currencies share are the hand-written part, and they must still win
        expectDisplay("=100 dollars to yen", "15,700.00 JPY")
        expectDisplay("=10 pounds to euros", "11.65 EUR")
        expectDisplay("=1 franc to usd", "1.23 USD")
        expectError("=1 peso to usd", "No exchange rate for MXN.")
        // `krona` is contested (SEK vs ISK) and deliberately assigned to neither
        expectNil("1 krona to usd")
        // Slang is no longer carried: CLDR has no "quid", and we don't hand-maintain synonyms
        expectNil("50 quid to usd")
        expectNil("100 bucks to eur")
        // The last word of a name isn't always its noun — "Special Drawing Rights" is not a "rights"
        expectNil("1 rights to usd")
        // A result too small to show at all reads as a clean zero, never "-0.00"
        expectDisplay("=-0.0000000000001 usd to eur", "0.00 EUR")
        expectDisplay("=0 usd to eur", "0.00 EUR")
        expectDisplay("=-5 usd to eur", "-4.60 EUR")
        // CUP (Cuban peso) is a generated code that collides with a unit; volume still wins
        expectDisplay("=1 cup to ml", "236.5882365 mL")
        expectDisplay("=1 cup to tbsp", "16 tbsp")

        // Currency expressions — still pure and deterministic against the injected rate table
        expectDisplay("=10$", "10.00 USD")
        expectExpression("=10$", "10 USD")
        expectBadges("=10$", source: "Expression", target: "US Dollar")
        expectDisplay("=$10 + $5", "15.00 USD")
        expectDisplay("=10$ + 5$", "15.00 USD")
        expectDisplay("=$10 + €5", "14.20 EUR")
        expectDisplay("=€5 + $10", "15.43 USD")
        // Sign-first money echoes amount-first, like every other quantity
        expectExpression("=$10 + €5", "10 USD + 5 EUR")
        expectExpression("=10$ + 5€", "10 USD + 5 EUR")
        expectDisplay("=$10 * 2", "20.00 USD")
        expectDisplay("=$10 / 4", "2.50 USD")
        expectDisplay("=$10 / $2", "5")
        expectDisplay("=$100 * 3%", "3.00 USD")
        expectDisplay("=3% * $100", "3.00 USD")
        expectDisplay("=$100 / 25%", "400.00 USD")
        expectDisplay("=($100 * 3%) to eur", "2.76 EUR")
        expectDisplay("=($10 + $5) to eur", "13.80 EUR")
        expectDisplay("=$10 +", "10.00 USD")
        expectBadges("=$10 +", source: "Expression", target: "US Dollar")
        // Juxtaposition multiplies on either side of the amount, same as an explicit "*"
        expectDisplay("=$5(2)", "10.00 USD")
        expectDisplay("=5(2)$", "10.00 USD")
        expectDisplay("=$5(2) to eur", "9.20 EUR")
        expectNilWithoutConsent("=$5(2)")
        expectNilWithoutConsent("=5(2)$")
        expectError("=$10 + 5kg", "Cannot add Currency and Weight.")
        expectErrorWithoutRates(
            "=$10 + $5", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "=$100 * 3%", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "=10$", "Exchange rates unavailable — check your connection.")

        // Consent gate: without it the currency path doesn't exist. Not an error card explaining a
        // feature the user never enabled — no card at all, so the query falls through to app search.
        expectNilWithoutConsent("=1 euro to dollars")
        expectNilWithoutConsent("=100 dollars to yen")
        expectNilWithoutConsent("=50 GBP in euros")
        expectNilWithoutConsent("=eur to usd")
        expectNilWithoutConsent("=€20 to GBP")
        expectNilWithoutConsent("=2*50 usd to cad")
        expectNilWithoutConsent("=1 zloty to eur")
        expectNilWithoutConsent("=10$")
        expectNilWithoutConsent("=$10 + $5")
        expectNilWithoutConsent("=$10 + €5")
        expectNilWithoutConsent("=$100 * 3%")
        expectNilWithoutConsent("=$10 +")
        expectNilWithoutConsent("=($10 + $5) to eur")
        expectNilWithoutConsent("=$10 + 5kg")
        // Even the friendly category error stays silent — it would leak that currency exists.
        expectNilWithoutConsent("=10 usd to kg")
        expectNilWithoutConsent("=10 kg to usd")
        // Everything that isn't currency is untouched by the gate.
        expectDisplayWithoutConsent("=10 pounds to kilograms", "4.5359237 kg")
        expectDisplayWithoutConsent("=10 pounds", "4.5359237 kg")
        expectDisplayWithoutConsent("=1 cup to ml", "236.5882365 mL")
        expectDisplayWithoutConsent("=10km to mi", "6.213711922 mi")
        expectDisplayWithoutConsent("=2+2", "4")
        expectDisplayWithoutConsent("=255 to hex", "0xFF")
        expectDisplayWithoutConsent("=20% off 500", "400")

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Fixed clock for deterministic date/time tests (Fri 2026-07-24 00:18:00 UTC)

    static let clock: (now: Date, calendar: Calendar) = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 24
        components.hour = 0
        components.minute = 18
        components.second = 0
        return (calendar.date(from: components)!, calendar)
    }()

    // MARK: - Fixed exchange rates so currency answers are deterministic

    /// NPR, ZMW and AFN are deliberately absent: the table recognizes them (they're in the generated
    /// list), so a query for one must reach "no exchange rate" rather than falling through to no card.
    static let fx = CurrencyRates(
        base: "USD",
        rates: [
            "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 157, "INR": 83.5, "CAD": 1.36,
            "KRW": 1330, "IDR": 18053, "CHF": 0.81, "AED": 3.6725,
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_785_000_000))

    // MARK: - Helpers

    static func expectDisplayAt(_ query: String, _ expected: String) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectBadgesAt(_ query: String, source: String, target: String) {
        guard let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar)
        else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    static func expectNilAt(_ query: String) {
        if let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    static func expectBadges(_ query: String, source: String, target: String) {
        guard let result = CalcEngine.evaluate(query, currency: .on(fx)) else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    static func expectDisplay(_ query: String, _ expected: String) {
        guard case .value(let display, _)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectCopy(_ query: String, _ expected: String) {
        guard case .value(_, let copy)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: copy)
    }

    static func expectError(_ query: String, _ expected: String) {
        guard case .error(let message)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// Consented, but no snapshot has landed yet — first run, or still offline.
    static func expectErrorWithoutRates(_ query: String, _ expected: String) {
        guard case .error(let message)? = CalcEngine.evaluate(query, currency: .on(nil))?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// No consent: the currency path must not engage. Checks the explicit `.off` source and the
    /// default argument, since a caller that forgets to pass one must still get the feature off.
    static func expectNilWithoutConsent(_ query: String) {
        if let result = CalcEngine.evaluate(query, currency: .off) {
            fail(query, expected: "nil (consent withheld)", got: "\(result.payload)")
        } else if let result = CalcEngine.evaluate(query) {
            fail(query, expected: "nil (default source)", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// A non-currency answer that must survive with the feature switched off.
    static func expectDisplayWithoutConsent(_ query: String, _ expected: String) {
        guard case .value(let display, _)? = CalcEngine.evaluate(query, currency: .off)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectExpression(_ query: String, _ expected: String) {
        guard let result = CalcEngine.evaluate(query, currency: .on(fx)) else {
            fail(query, expected: expected, got: "nil")
            return
        }
        check(query, expected: expected, got: result.expression)
    }

    static func expectVector(_ query: String, _ expected: String) {
        guard case .value(let display, _)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectVectorCopy(_ query: String, _ expected: String) {
        guard case .value(_, let copy)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: copy)
    }

    static func expectNil(_ query: String) {
        if let result = CalcEngine.evaluate(query, currency: .on(fx)) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    static func check(_ query: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            fail(query, expected: expected, got: got)
        }
    }

    static func fail(_ query: String, expected: String, got: String) {
        failures += 1
        print("FAIL  \(query)\n      expected: \(expected)\n      got:      \(got)")
    }

    // MARK: - Benchmark

    static func runBenchmark() {
        let appQueries = [
            "safari", "terminal", "firefox", "chrome", "slack",
            "discord", "zoom", "notion", "figma", "linear",
            "things", "bear", "craft", "spotify", "mail",
            "calendar", "notes", "reminders", "messages", "facetime",
        ]

        let calcQueries = [
            "2+2", "10km to mi", "100 C to F", "1 euro to dollars", "20% off 500",
            "255 to hex", "sqrt(64)", "2^10", "5*7", "100/4",
            "hrs till 9am", "day to s", "sin(30deg)", "log(1000)", "10k + 500",
        ]

        let iterations = 1000

        // Warmup
        for q in appQueries { _ = CalcEngine.evaluate(q) }
        for q in calcQueries { _ = CalcEngine.evaluate(q, currency: .on(fx)) }

        // Benchmark app queries — measure total batch time for precision
        var totalApp: Double = 0
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            for q in appQueries {
                _ = CalcEngine.evaluate(q)
            }
            totalApp += CFAbsoluteTimeGetCurrent() - start
        }
        let appCount = Double(appQueries.count * iterations)
        let appAvg = totalApp / appCount * 1_000_000

        // Benchmark calc queries
        var totalCalc: Double = 0
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            for q in calcQueries {
                _ = CalcEngine.evaluate(q, currency: .on(fx))
            }
            totalCalc += CFAbsoluteTimeGetCurrent() - start
        }
        let calcCount = Double(calcQueries.count * iterations)
        let calcAvg = totalCalc / calcCount * 1_000_000

        print("app-query avg: \(String(format: "%.1f", appAvg))µs")
        print("calc-query avg: \(String(format: "%.1f", calcAvg))µs")
    }
}
