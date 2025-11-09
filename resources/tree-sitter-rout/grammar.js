module.exports = grammar({
    name: 'rout',

    // Define extras (like whitespace) that can appear between tokens
    extras: $ => [
        /\s+/
    ],

    rules: {
        // 1. Entry point rule
        source_file: $ => repeat(
            choice(
                $.routNormal,
                // $.routConst,
                $.routNumber,
                $.routNegNum,
                $.routTrue,
                $.routFalse,
                $.routInf
            )
        ),

        routNormal: $ => token(/[^\s\d\-]\S*/),

        routNumber: $ => token(prec(3, seq(
            /\d+/,
            optional(seq(
                '.',
                /\d+/
            )),
            optional(seq(
                /[eE]/, // 'e' or 'E'
                optional(/[+-]/), // Optional sign for the exponent
                /\d+/ // The exponent digits
            ))
        ))),

        routNegNum: $ => token(prec(3, seq(
            /-\d+/,
            optional(seq(
                '.',
                /\d+/
            )),
            optional(seq(
                /[eE]/, // 'e' or 'E'
                optional(/[+-]/), // Optional sign for the exponent
                /\d+/ // The exponent digits
            ))
        ))),

        // routConst: $ => choice(
        //     $.null_const,
        //     $.nan_const,
        //     $.na_const
        // ),
        // null_const: $ => prec(5, token("NULL")),
        // nan_const: $ => prec(5, token("NaN")),
        // na_const: $ => prec(5, token("NA")),

        routTrue: $ => prec(5, token("TRUE")),
        routFalse: $ => prec(6, token("FALSE")),
        routInf: $ => token(prec(6, seq(optional('-'), 'Inf')))

    }
});
