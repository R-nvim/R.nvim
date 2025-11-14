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
                $.routNumber,
                $.routNegNum,
                $.routPunct,
                $.routWPunct,
                $.routNotNum,
                $.routTrue,
                $.routFalse,
                $.routInf,
            )
        ),

        routNormal: $ => token(prec(1, /\S+[^:$%#]/)),

        routPunct: $ => token(prec(7, /[:\$%#]/)),
        routWPunct: $ => token(prec(7, /\w+[\.,!?=:\$%#]/)),
        routNotNum: $ => token(prec(9, /\d+[a-zA-Z]\w*/)),

        routNumber: $ => token(prec(8, seq(
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

        routNegNum: $ => token(prec(8, seq(
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


        routTrue: $ => token(prec(9, "TRUE")),
        routFalse: $ => token(prec(9, "FALSE")),
        routInf: $ => token(prec(9, seq(optional('-'), 'Inf')))

    }
});
