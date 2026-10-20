#!/usr/bin/env python3
"""Small Molang parser + interpreter used to test Ultra Clouds offline.

Implements the subset of Molang used by the pack, following the official
syntax guide (case-insensitive identifiers, `;` statements, `{}` scopes,
binary/ternary conditionals, `??`, degree-based trigonometry, booleans as
1.0/0.0, temp.* variables scoped to one expression execution).
"""
import math
import re

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)|
    (?P<num>\d+\.\d*|\.\d+|\d+)(?:f)?|
    (?P<str>'[^']*')|
    (?P<id>[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)|
    (?P<op>\?\?|->|&&|\|\||==|!=|<=|>=|[-+*/<>!?:;(){},\[\]=])
""", re.X)


class MolangError(Exception):
    pass


def tokenize(src):
    pos, out = 0, []
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise MolangError(f"unexpected character {src[pos]!r} at {pos} in: {src[max(0, pos-40):pos+40]}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        val = m.group(kind)
        if kind == "id":
            val = val.lower()
        out.append((kind, val))
    out.append(("eof", None))
    return out


# precedence (higher binds tighter)
BINARY = {
    "??": 1, "||": 2, "&&": 3,
    "==": 4, "!=": 4,
    "<": 5, "<=": 5, ">": 5, ">=": 5,
    "+": 6, "-": 6,
    "*": 7, "/": 7,
}


class Parser:
    def __init__(self, src):
        self.src = src
        self.toks = tokenize(src)
        self.i = 0

    def peek(self, k=0):
        return self.toks[self.i + k]

    def take(self, val=None):
        t = self.toks[self.i]
        if val is not None and t[1] != val:
            raise MolangError(f"expected {val!r} got {t[1]!r} in: {self.src[:160]}")
        self.i += 1
        return t

    def parse_program(self):
        stmts = self.parse_statements(end=("eof",))
        self.take()
        return ("prog", stmts)

    def parse_statements(self, end):
        stmts = []
        while True:
            t = self.peek()
            if t[0] in end or t[1] in end:
                break
            if t[1] == ";":
                self.take()
                continue
            stmts.append(self.parse_statement())
            if self.peek()[1] == ";":
                self.take()
            elif self.peek()[0] not in end and self.peek()[1] not in end:
                raise MolangError(f"missing ';' before {self.peek()[1]!r} in: {self.src[:200]}")
        return stmts

    def parse_statement(self):
        if self.peek() == ("id", "return"):
            self.take()
            return ("return", self.parse_expr())
        return self.parse_expr()

    def parse_expr(self):
        return self.parse_assign()

    def parse_assign(self):
        left = self.parse_ternary()
        if self.peek()[1] == "=":
            if left[0] != "var":
                raise MolangError(f"invalid assignment target in: {self.src[:160]}")
            self.take()
            right = self.parse_assign()
            return ("assign", left[1], right)
        return left

    def parse_ternary(self):
        cond = self.parse_binary(1)
        if self.peek()[1] == "?":
            self.take()
            a = self.parse_branch()
            if self.peek()[1] == ":":
                self.take()
                b = self.parse_branch()
                return ("tern", cond, a, b)
            return ("cond", cond, a)
        return cond

    def parse_branch(self):
        if self.peek()[1] == "{":
            return self.parse_block()
        return self.parse_ternary()

    def parse_block(self):
        self.take("{")
        stmts = self.parse_statements(end=("}",))
        self.take("}")
        return ("block", stmts)

    def parse_binary(self, minp):
        left = self.parse_unary()
        while True:
            op = self.peek()[1]
            p = BINARY.get(op)
            if p is None or p < minp or self.peek()[0] != "op":
                return left
            self.take()
            right = self.parse_binary(p + 1)
            left = ("bin", op, left, right)

    def parse_unary(self):
        t = self.peek()
        if t[1] in ("-", "!") and t[0] == "op":
            self.take()
            return ("un", t[1], self.parse_unary())
        return self.parse_primary()

    def parse_primary(self):
        kind, val = self.take()
        if kind == "num":
            return ("num", float(val))
        if kind == "str":
            return ("str", val[1:-1])
        if kind == "op" and val == "(":
            e = self.parse_expr()
            self.take(")")
            return e
        if kind == "op" and val == "{":
            self.i -= 1
            return self.parse_block()
        if kind == "id":
            if val in ("true", "false"):
                return ("num", 1.0 if val == "true" else 0.0)
            if val in ("break", "continue"):
                return (val,)
            if self.peek()[1] == "(":
                self.take("(")
                args = []
                if self.peek()[1] != ")":
                    while True:
                        args.append(self.parse_expr())
                        if self.peek()[1] == ",":
                            self.take()
                            continue
                        break
                self.take(")")
                return ("call", val, args)
            return ("var", val)
        raise MolangError(f"unexpected token {val!r} in: {self.src[:200]}")


def normalize_name(name):
    for long, short in (("variable.", "v."), ("temp.", "t."), ("query.", "q."), ("context.", "c.")):
        if name.startswith(long):
            return short + name[len(long):]
    return name


def walk(node, fn):
    fn(node)
    for child in node[1:]:
        if isinstance(child, tuple):
            walk(child, fn)
        elif isinstance(child, list):
            for c in child:
                if isinstance(c, tuple):
                    walk(c, fn)


def parse(src):
    if isinstance(src, (int, float, bool)):
        return ("prog", [("num", float(src))])
    return Parser(str(src)).parse_program()


class Missing(Exception):
    pass


class Env:
    """Evaluation context: entity variables persist, temps are per call."""

    def __init__(self, queries=None):
        self.vars = {}
        self.queries = queries or {}
        self.ops = 0

    def run(self, prog):
        self.temps = {}
        try:
            return self._stmts(prog[1])
        except _Return as r:
            return r.value

    def _stmts(self, stmts):
        val = 0.0
        for s in stmts:
            if s[0] == "return":
                raise _Return(self.ev(s[1]))
            val = self.ev(s)
        # simple expressions return their value; complex ones need 'return'
        return val if len(stmts) == 1 else 0.0

    def lookup(self, name):
        name = normalize_name(name)
        if name.startswith("v."):
            if name not in self.vars:
                raise Missing(name)
            return self.vars[name]
        if name.startswith("t."):
            if name not in self.temps:
                raise Missing(name)
            return self.temps[name]
        if name.startswith("q."):
            return self.query(name, [])
        if name == "math.pi":
            return math.pi
        raise MolangError(f"unknown identifier {name}")

    def query(self, name, args):
        q = self.queries.get(name)
        if q is None:
            raise MolangError(f"query {name} not provided by the test harness")
        return float(q(*args)) if callable(q) else float(q)

    def ev(self, n):
        self.ops += 1
        k = n[0]
        if k == "num":
            return n[1]
        if k == "str":
            return n[1]
        if k == "var":
            try:
                return self.lookup(n[1])
            except Missing:
                return 0.0
        if k == "assign":
            name = normalize_name(n[1])
            val = self.ev(n[2])
            (self.temps if name.startswith("t.") else self.vars)[name] = val
            return val
        if k == "un":
            v = self.ev(n[2])
            return -v if n[1] == "-" else (0.0 if v else 1.0)
        if k == "bin":
            op = n[1]
            if op == "??":
                try:
                    if n[2][0] == "var":
                        return self.lookup(n[2][1])
                    return self.ev(n[2])
                except Missing:
                    return self.ev(n[3])
            if op == "&&":
                return 1.0 if (self.ev(n[2]) and self.ev(n[3])) else 0.0
            if op == "||":
                return 1.0 if (self.ev(n[2]) or self.ev(n[3])) else 0.0
            a, b = self.ev(n[2]), self.ev(n[3])
            if op == "+": return a + b
            if op == "-": return a - b
            if op == "*": return a * b
            if op == "/": return a / b if b != 0 else 0.0
            if op == "<": return 1.0 if a < b else 0.0
            if op == "<=": return 1.0 if a <= b else 0.0
            if op == ">": return 1.0 if a > b else 0.0
            if op == ">=": return 1.0 if a >= b else 0.0
            if op == "==": return 1.0 if a == b else 0.0
            if op == "!=": return 1.0 if a != b else 0.0
        if k == "tern":
            return self.ev(n[2]) if self.ev(n[1]) else self.ev(n[3])
        if k == "cond":
            return self.ev(n[2]) if self.ev(n[1]) else 0.0
        if k == "block":
            for s in n[1]:
                if s[0] == "return":
                    raise _Return(self.ev(s[1]))
                self.ev(s)
            return 0.0
        if k == "call":
            return self.call(n[1], [a for a in n[2]])
        raise MolangError(f"cannot evaluate {k}")

    def call(self, name, argnodes):
        name = normalize_name(name)
        if name.startswith("q."):
            args = [self.ev(a) for a in argnodes]
            return self.query(name, args)
        a = [self.ev(x) for x in argnodes]
        f = MATH.get(name)
        if f is None:
            raise MolangError(f"unknown function {name}")
        return f(*a)


class _Return(Exception):
    def __init__(self, value):
        self.value = value


def _lerprotate(a, b, t):
    d = ((b - a + 180.0) % 360.0) - 180.0
    return a + d * t


MATH = {
    "math.abs": abs,
    "math.sin": lambda x: math.sin(math.radians(x)),
    "math.cos": lambda x: math.cos(math.radians(x)),
    "math.atan2": lambda y, x: math.degrees(math.atan2(y, x)),
    "math.sqrt": lambda x: math.sqrt(x) if x >= 0 else 0.0,
    "math.clamp": lambda v, lo, hi: min(hi, max(lo, v)),
    "math.min": min,
    "math.max": max,
    "math.floor": math.floor,
    "math.ceil": math.ceil,
    "math.round": lambda x: math.floor(x + 0.5),
    "math.mod": math.fmod,
    "math.lerp": lambda a, b, t: a + (b - a) * t,
    "math.lerprotate": _lerprotate,
    "math.exp": lambda x: math.exp(min(x, 80.0)),
    "math.ln": lambda x: math.log(x) if x > 0 else -1e30,
    "math.pow": lambda a, b: math.pow(a, b) if a >= 0 or float(b).is_integer() else 0.0,
    "math.sign": lambda x: 1.0 if x > 0 else (-1.0 if x < 0 else 0.0),
}
