#pragma DefaultVisibility=public
#pragma PrimitiveLists
import "io" as io
import "sys" as sys
import "ast" as ast
import "util" as util
import "xmodule" as xmodule
import "stringMap" as map
import "mirrors" as mirrors
import "errormessages" as errormessages
import "identifierKinds" as k

def emptySequence = sequence.empty

def completed = Singleton.named "completed"
def inProgress = Singleton.named "inProgress"
def undiscovered = Singleton.named "undiscovered"
// constants used in detecting cyclic inheritance

var stSerial := 100

def reserved = sequence.with("self", "super", "outer", "true", "false")
// reserved names that cannot be re-assigned or re-declared

method newScopeKind(variety') {
    // for the top of the scope chain
    def s = newScopeIn(object {})kind(variety')
    s.hasParent := false
    s
}
type DeclKind = k.T

factory method newScopeIn(parent') kind(variety') {
    def elements = map.new
    def elementScopes = map.new
    def elementLines = map.new
    def elementTokens = map.new
    def parent = parent'
    var hasParent := true
    def variety = variety'
    var node := ast.nullNode        // the outermost ast node that I'm in
    var inheritedNames := undiscovered
    stSerial := stSerial + 1
    def serialNumber is public = stSerial
    def hash is public = serialNumber.hash
    
    if (isObjectScope) then {
        addName "self" as(k.defdec)
        at "self" putScope(self)
    }
    method isEmpty { elements.size == 0 }
    method addName(n) {
        elements.put(n, k.methdec)
        elementLines.put(n, util.linenum)
    }
    method addName(n)as(kind:DeclKind) {
        elements.put(n, kind)
        elementLines.put(n, util.linenum)
    }
    method addNode(nd) as(kind:DeclKind) {
        def ndName = nd.value
        checkShadowing(nd) as(kind)
        def oldKind = elements.get(ndName) ifAbsent {
            elements.put(ndName, kind)
            elementLines.put(ndName, nd.line)
            return
        }
        if (kind == k.inherited) then {
            return  // don't overwrite new id with inherited id
        }
        if (oldKind == k.inherited)  then {
            elements.put(ndName, kind)
            elementLines.put(ndName, nd.line)
            return
        } 
        var more := " in this scope"
        if (elementLines.contains(ndName)) then {
            more := " as a {oldKind}"
                ++ " on line {elementLines.get(ndName)}"
        }
        errormessages.syntaxError("'{ndName}' cannot be"
            ++ " redeclared because it is already declared"
            ++ more ++ " as well as here at line {nd.line}.")
            atRange(nd.line, nd.linePos, nd.linePos + ndName.size - 1)
    }
    method contains(n) {
        elements.contains(n)
    }
    method do(b) {
        var cur := self
        while {b.apply(cur); cur.hasParent} do {
            cur := cur.parent
        }
    }
    method keysAsList {
        def result = list.empty
        elements.keysDo { each -> result.addLast(each) }
        result
    }
    method keysAndValuesAsList {
        elements.asList
    }
    method kind(n) {
        def kd:DeclKind = elements.get(n)
        if (DeclKind.match(kd).not) then { print "kind of {n} is {k}" }
        kd
    }
    method at(n) putScope(scp) {
        elementScopes.put(n, scp)
    }
    method getScope(n) {
        if (elementScopes.contains(n)) then {
            return elementScopes.get(n)
        }
        //    print("scope {self}: elements.contains({n}) = {elements.contains(n)}" ++
        //        " but elementScopes.contains({n}) = {elementScopes.contains(n)}")
        //  This occurs for names like `true` that are built-in, but for which there
        //  is no symbolTable describing their atttributes.
        //  TODO: add complete information for the built-in names.
        //  in the meantime:
        return universalScope
    }
    method asStringWithParents {
        var result := "\nCurrent: {self}"
        var s := self
        while {s.hasParent} do {
            s := s.parent
            result := result ++ "\nParent: {s}"
        }
        result ++ "\n"
    }
    method asString {
        var result := "({variety} ST: "
        self.do { each -> 
            result := result ++ each.serialNumber
            if (each.hasParent) then { result := result ++ "➞" }
        }
        result := result ++  "):\n"
        elements.asList.sortBy { a, b -> a.key.compare(b.key) }.do { each ->
            result := "{result} {each.key}({kind(each.key)}) "
        }
        result ++ "\n"
    }
    
    method asDebugString { "(ST {serialNumber})" }

    method elementScopesAsString {
        def referencedScopes = set.empty
        var result := "\n    [elementScopes:"
        elementScopes.asList.sortBy { a, b -> a.key.compare(b.key) }.do { each ->
            result := "{result} {each.key}➞{each.value.asDebugString}"
            referencedScopes.add (each.value)
        }
        result := result ++ "]\n____________\n"
        referencedScopes.asList
            .sortBy { a, b -> a.serialNumber.compare(b.serialNumber) }
                .do { each -> result := result ++ each.asString }
        result ++ "____________\n"
    }
    method hasDefinitionInNest(nm) {
        self.do { s ->
            if (s.contains(nm)) then {
                return true
            }
        }
        return false
    }
    method kindInNest(nm) {
        self.do {s->
            if (s.contains(nm)) then {
                def kd = s.kind(nm)
                if (kd == k.inherited) then {
                    return k.methdec
                } else {
                    return kd
                }
            }
        }
        return k.undefined
    }
    method thatDefines(name) ifNone(action) {
        self.do { s->
            if (s.contains(name)) then { return s }
        }
        action.apply
    }
    method thatDefines(name) {
        self.do { s->
            if (s.contains(name)) then { return s }
        }
        print(self.asStringWithParents)
        ProgrammingError.raise "no scope defines {name}"
    }
    method isInSameObjectAs (enclosingScope) {
        if (self == enclosingScope) then { return true }
        if (self.parent.isObjectScope) then { return false }
        self.parent.isInSameObjectAs(enclosingScope)
    }
    method isObjectScope {
        if (variety == "object") then { return true }
        if (variety == "module") then { return true }
        if (variety == "dialect") then { return true }
        if (variety == "class") then { return true }
        if (variety == "built-in") then { return true }
        false
    }
    method isMethodScope {
        variety == "method"
    }
    method resolveOuterMethod(name) {
        // replace name by outer.outer. ... .name,
        // depending on where name is declared.
        var mem := ast.identifierNode.new("self", false) scope(self)
        self.do { s->
            if (s.contains(name)) then {
                if (s.variety == "dialect") then {
                    return ast.memberNode.new(name,
                        ast.identifierNode.new("prelude", false) scope(self)) scope(self)
                }
                return ast.memberNode.new(name, mem) scope(self)
            }
            match ( s.variety
            ) case { "object" ->
                mem := ast.memberNode.new("outer", mem) scope(self)
            } case { "class" ->
                mem := ast.memberNode.new("outer", mem) scope(self)
                mem := ast.memberNode.new("outer", mem) scope(self)
            } case { _ -> }
        }
        // Not found - leave it alone
        return ast.identifierNode.new(name, false) scope(self)
    }
    method scopeReferencedBy(nd) {
        // Finds the scope referenced by astNode nd.
        // If nd references an object, then the returned
        // scope will have bindings for the methods of that object.
        // Otherwise, it will be the empty scope.
        if (nd.kind == "identifier") then {
            def sought = nd.nameString
            self.do {s->
                if (s.contains(sought)) then {
                    return s.getScope(sought)
                }
            }
            errormessages.syntaxError "No method {sought}"
                atRange(nd.line, nd.linePos, nd.linePos + sought.size - 1)
        } elseif {nd.kind == "member"} then {
            def receiverScope = self.scopeReferencedBy(nd.in)
            if (nd.value == "outer") then {
                return receiverScope.parent
            }
            return receiverScope.scopeReferencedBy(nd.asIdentifier)
        } elseif {nd.kind == "call"} then {
            return scopeReferencedBy(nd.value)
        } elseif {nd.kind == "op"} then {
            def receiverScope = self.scopeReferencedBy(nd.left)
            return receiverScope.scopeReferencedBy(nd.asIdentifier)
        }
        ProgrammingError.raise("{nd.value} is not a Call, Member or Identifier\n"
            ++ nd.pretty(0))
    }
    method enclosingObjectScope {
        // Answer the closest enclosing scope that describes an
        // object, class or module.  Could answer self.
        self.do { s ->
            if (s.isObjectScope) then { return s }
        }
        ProgrammingError "no object scope found!"
        // the outermost scope should always be a module scope,
        // which is an object scope.
    }
    method inSameContextAs(encScope) {
        // Is this scope within the same context as encScope?
        // i.e. within the same method and object?
        if (encScope.isObjectScope) then { return false }
        self.do { s ->
            if (s == encScope) then { return true }
            if (s.isObjectScope) then { return false }
            if (s.isMethodScope) then { return false }
        }
        ProgrammingError.raise "self = {self}; encScope = {encScope}"
    }
    method isUniversal { false }
    method checkShadowing(ident) as(newKind) {
        def name = ident.nameString
        def priorScope = thatDefines(name) ifNone {
            return
        }
        def description = 
            if (priorScope == self) then {
                "this"
            } else {
                "an enclosing {priorScope.variety}"
            }
        def priorKind = priorScope.kind(name)
        if (priorScope.isObjectScope.andAlso{self.isObjectScope}) then {
            return
        }
        // new object attributes can shadow old, but other shadowing is illegal
        var more := ""
        if (priorScope.elementLines.contains(name)) then {
            def ln = priorScope.elementLines.get(name)
            if (ln > 0) then {
                more := " on line {priorScope.elementLines.get(name)}"
            }
        }
        if (newKind == k.vardec) then {
            def suggs = list.empty
            def sugg = errormessages.suggestion.new
            if (sugg.replaceUntil("=")with("{name} :=")
                    onLine(ident.line)
                ) then {
                suggs.push(sugg)
            }
            if (priorKind == k.vardec) then {
                more := more ++ ". To assign to the existing variable, remove 'var'"
            }
            errormessages.syntaxError("'{name}' cannot be "
                ++ "redeclared because it is already declared in "
                ++ "{description} scope{more}.")
                atRange(ident.line, ident.linePos, ident.linePos + name.size - 1)
                withSuggestions(suggs)
        } else {
            errormessages.syntaxError("'{name}' cannot be "
                ++ "redeclared because it is already declared in "
                ++ "{description} scope{more}. Use a different name.")
                atRange(ident.line, ident.linePos,
                    ident.linePos + name.size - 1)
        }
    }
}

def emptyScope = newScopeKind("empty")
ast.nullNode.scope := emptyScope      // TODO: eliminate!
def builtInsScope = newScopeIn(emptyScope) kind("built-in")
def preludeScope = newScopeIn(builtInsScope) kind("dialect")
def moduleScope = newScopeIn(preludeScope) kind("module")
def graceObjectScope = newScopeIn(emptyScope) kind("object")

def universalScope = object {
    // The scope that defines every identifier,
    // used when we have no information about an object
    inherits newScopeIn(emptyScope) kind("universal")
    method hasParent { false }
    method parent { ProgrammingError.raise "universal scope has no parent" }
    method addName(n) { ProgrammingError.raise "can't add to the universal scope" }
    method addName(n)as(kd) { ProgrammingError.raise "can't add to the universal scope" }
    method addNode(n)as(kd) { ProgrammingError.raise "can't add to the universal scope" }
    method contains(n) { true }
    method do(b) { b.apply(self) }
    method kind(n) { "unknown" }
    method at(n) putScope(scp) { }
    method getScope(n) { self }
    method isUniversal { true }
}

method rewritematchblockterm(arg) {
    util.setPosition(arg.line, arg.linePos)
    if (arg.kind == "num") then {
        return [arg, []]
    }
    if (arg.kind == "string") then {
        return [arg, []]
    }
    if (arg.kind == "boolean") then {
        return [arg, []]
    }
    if ((arg.kind == "call").andAlso {arg.value.value.substringFrom(1)to(6)
        == "prefix"}) then {
        return [arg, []]
    }
    if (arg.kind == "member") then {
        return [arg, []]
    }
    if (arg.kind == "call") then {
        def bindings = []
        def subpats = []
        for (arg.with) do { part ->
            for (part.args) do { a ->
                def tmp = rewritematchblockterm(a)
                subpats.push(tmp[1])
                for (tmp[2]) do {b->
                    bindings.push(b)
                }
            }
        }
        def callpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("MatchAndDestructuringPattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.request "new" withArgs( [arg.value, ast.arrayNode.new(subpats)] )]
        )
        return [callpat, bindings]
    }
    if (arg.kind == "identifier") then {
        def varpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("VariablePattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.request "new" withArgs( [ast.stringNode.new(arg.value)] )]
        )
        if (arg.dtype != false) then {
            if (arg.dtype.kind == "identifier") then {
                return [ast.callNode.new(
                    ast.memberNode.new(
                        "new",
                        ast.memberNode.new("AndPattern",
                            ast.identifierNode.new("prelude", false)
                        )
                    ),
                    [ast.callWithPart.request "new" withArgs( [varpat, arg.dtype] )]
                ), [arg]]
            }
            def tmp = rewritematchblockterm(arg.dtype)
            def bindings = [arg]
            for (tmp[2]) do {b->
                bindings.push(b)
            }
            def bindingpat = ast.callNode.new(
                ast.memberNode.new(
                    "new",
                    ast.memberNode.new("AndPattern",
                        ast.identifierNode.new("prelude", false)
                    )
                ),
                [ast.callWithPart.request "new" withArgs( [varpat, tmp[1]] )]
            )
            return [bindingpat, bindings]
        }
        return [varpat, [arg]]
    }
    if (arg.kind == "typeliteral") then {
        return [arg, []]
    }
    ProgrammingError.raise("Internal error in compiler: fell through when rewriting "
        ++ "match block of unexpected kind '{arg.kind}'.")
}
method rewritematchblock(blk) {
    def arg = blk.params[1]
    var pattern := false
    var newparams := list.empty
    for (blk.params) do { p ->
        newparams.push(p)
    }
    if ((arg.kind == "num") || (arg.kind == "string") ||
        (arg.kind == "boolean")) then {
        def tmp = rewritematchblockterm(arg)
        pattern := tmp[1]
        newparams := tmp[2]
    }
    if (arg.kind == "identifier") then {
        def varpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("VariablePattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.request "new" withArgs( [ast.stringNode.new(arg.value)] )]
        )
        if (arg.dtype != false) then {
            match (arg.dtype.kind)
                case { "identifier" | "op" ->
                    pattern := ast.callNode.new(
                        ast.memberNode.new("new",
                            ast.memberNode.new("AndPattern",
                                ast.identifierNode.new("prelude", false)
                                )
                            ),
                        [ast.callWithPart.request "new" withArgs( [varpat, arg.dtype] )])
                } case { _ ->
                    def tmp = rewritematchblockterm(arg.dtype)
                    def bindingpat = ast.callNode.new(
                        ast.memberNode.new("new",
                            ast.memberNode.new("AndPattern",
                                ast.identifierNode.new("prelude", false)
                                )
                            ),
                        [ast.callWithPart.request "new" withArgs( [varpat, tmp[1]] )]
                    )
                    pattern := bindingpat
                    for (tmp[2]) do {p->
                        // We can't name both p and the extra param binding
                        // occurences, because then there would be shadowing.
                        if (p.wildcard) then {
                            p.isBindingOccurrence := true
                        } else {
                            def extraParam = p.deepCopy
                            // The deepCopy copies the type too.
                            // Does this cause an unnecessary dynamic type-check?
                            extraParam.isBindingOccurrence := true
                            newparams.push(extraParam)
                        }
                    }
                }
        } else {
            if (false != blk.matchingPattern) then {
                if (blk.matchingPattern.value == arg.value) then {
                    pattern := arg
                    newparams := []
                }
            }
        }
    } else {
        if (false != blk.matchingPattern) then {
            if (blk.matchingPattern.value == arg.value) then {
                pattern := arg
                newparams := []
            }
        }
    }
    def newblk = ast.blockNode.new(newparams, blk.body)
    newblk.matchingPattern := pattern
    newblk.line := blk.line
    return newblk
}

method rewriteIdentifier(node) ancestors(as) {
    // node is a (copy of an) ast node that represents an applied occurence of
    // an identifer id.   This implies that node is a leaf in the ast.
    // This method may or may not transform node into another ast.
    // There is no spec for what this method should do.  The code below 
    // was developed by addding and removing particular cases until
    // the transformed AST was sufficiecntly similar to the one emitted by the
    // old identifier resolution pass for the C code generator to accept it.
    // This method seems to do the following:
    // - id is self => do nothing
    // - id is super => do nothing
    // - id is in an assignment position and a method ‹id›:= is in scope:
    //          replace node by a method request
    // - id is in the lexical scope: store binding occurence of id in node
    // - id is a method in an outer object scope: transform into member nodes.
    //  TODO: can't make references to fields direct because they might be overridden
    // - id is a self-method: transform into a request on self
    // - id is not declared: generate an error message
    
    // Some clauses are flagged "TODO Compatability Kludge — remove when possible"
    // This means that APB put them there to produce an AST close enough to the
    // former identifier resolution pass to keep the C code generator (genc) happy.
    // They may represent things that APB doesn't understand, or bugs in genc

    var nm := node.value
    def nodeScope = node.scope
    def nmGets = nm ++ ":="
    util.setPosition(node.line, node.linePos)
    if (node.isAssigned) then {
        if (nodeScope.hasDefinitionInNest(nmGets)) then {
            if (nodeScope.kindInNest(nmGets) == k.methdec) then {
                def meth = nodeScope.resolveOuterMethod(nmGets)
                def meth2 = ast.memberNode.new(nm, meth.in)
                return meth2
            }
        }
    }
    def definingScope = nodeScope.thatDefines(nm) ifNone {
        reportUndeclaredIdentifier(node)
    }
    def nodeKind = definingScope.kind(nm)
    if (node.isAssigned) then {
        if (nodeKind.isAssignable.not) then {
            reportAssignmentTo(node) declaredInScope(definingScope)
        }
    }
    if (nm == "outer") then {
        def selfId = ast.identifierNode.new("self", false) scope(nodeScope)
        def memb = ast.memberNode.new("outer", selfId) scope(nodeScope)
        return memb
        // TODO: represent outer statically
    }
    if (nm == "self") then {
        return node
    }
    checkForAmbiguityOf (node) definedIn (definingScope) as (nodeKind)
    def v = definingScope.variety
    if (v == "built-in") then { return node }
    if (v == "dialect") then {
        def p = ast.identifierNode.new("prelude", false) scope(nodeScope)
        def m = ast.memberNode.new(nm, p) scope(nodeScope)
        return m
    }
    if (nodeKind.isParameter) then { return node }
    if (nodeKind == k.typedec) then { return node }

    // TODO Compatability Kludge — remove when possible
    if (node.inTypePositionWithAncestors(as)) then { return node }
    // the latter is necessary until .gct files distinguish types

    if (definingScope == moduleScope) then {
        if (nodeKind == k.defdec) then { return node }
        if (nodeKind == k.typedec) then { return node }
        if (nodeKind == k.vardec) then { return node }
    }
    if (definingScope == nodeScope.enclosingObjectScope) then {
        return ast.memberNode.new(nm, 
            ast.identifierNode.new("self", false) scope(nodeScope)
        ) scope(nodeScope)
    }
    if (nodeScope.isObjectScope.not
            .andAlso{nodeScope.isInSameObjectAs(definingScope)}) then {
        if (nodeKind == k.methdec) then { return node }
        if (nodeKind == k.defdec) then { return node }
        if (nodeKind == k.vardec) then { return node }
    }
    if (v == "method") then { return node }
        // node is defined in the closest enclosing method.
        // there may be intervening blocks, but no objects or clases.
        // If this identifier is in a block that is returned, then ids
        // defined in the enclosing method scope have to go in a closure
        // In that case, leaving the id untouched may be wrong
    if (v == "block") then { return node }
    return nodeScope.resolveOuterMethod(nm)
}
method checkForAmbiguityOf(node)definedIn(definingScope)as(kind) {
    def currentScope = node.scope
    if (currentScope != definingScope) then { return done }
    // TODO This isn't quite right:  currentScope might be a block (or method)
    // node might be defined by inheritance in the object containing currentScope,
    // and also in an enclosing scope.
    if (kind != k.inherited) then { return done }
    def name = node.value
    def conflictingScope = currentScope.parent.thatDefines(name) ifNone {
        return
    }
    def more = if (conflictingScope.elementLines.contains(name)) then {
        " at line {conflictingScope.elementLines.get(name)}"
    } else { 
        ""
    }
    errormessages.syntaxError "{name} is defined both by inheritance and by an enclosing scope{more}."
        atRange(node.line, node.linePos, node.linePos + name.size)
}
method checkForReservedName(node) {
    def ns = node.nameString
    if (reserved.contains(ns)) then {
        errormessages.syntaxError "{ns} is a reserved name and cannot be re-declared."
            atRange(node.line, node.linePos, node.linePos + ns.size - 1)
    }
}
method reportUndeclaredIdentifier(node) {
    def nodeScope = node.scope
    def nm = node.nameString
    def suggestions = []
    var suggestion
    nodeScope.elements.keysDo { v ->
        var thresh := 1
        if (nm.size > 2) then {
            thresh := ((nm.size / 3) + 1).truncated
        }
        if (errormessages.dameraulevenshtein(v, nm) <= thresh) then {
            suggestion := errormessages.suggestion.new
            suggestion.replaceRange(node.linePos, node.linePos + 
                node.value.size - 1)with(v)onLine(node.line)
            suggestions.push(suggestion)
        }
    }
    nodeScope.elementScopes.keysDo { s ->
        if (nodeScope.elementScopes.get(s).contains(nm)) then {
            suggestion := errormessages.suggestion.new
            suggestion.insert("{s}.")atPosition(node.linePos)onLine(node.line)
            suggestions.push(suggestion)
        }
    }
    var highlightLength := node.value.size
    if (node.value.replace "()" with "XX" != node.value) then {
        var i := 0
        var found := false
        for (node.value) do {c->
            if ((c == "(") && (!found)) then {
                highlightLength := i
                found := true
            }
            i := i + 1
        }
    }
    if (node.inRequest) then {
        var extra := ""
        if (node.value == "while") then {
            suggestion := errormessages.suggestion.new
            suggestion.append " do \{ \}" onLine(node.line)
            suggestions.push(suggestion)
        }
        if (node.value == "for") then {
            suggestion := errormessages.suggestion.new
            suggestion.append " do \{ aVarName -> \}" onLine(node.line)
            suggestions.push(suggestion)
        }
        errormessages.syntaxError "Unknown method '{nm}'. This may be a spelling mistake or an attempt to access a method in another scope.{extra}"
            atRange(node.line, node.linePos, node.linePos +
                highlightLength - 1)
            withSuggestions(suggestions)
    }
    errormessages.syntaxError("Unknown variable or method '{nm}'. This may be a spelling mistake or an attempt to access a variable in another scope.")atRange(
        node.line, node.linePos, node.linePos + highlightLength - 1)withSuggestions(suggestions)
}
method reportAssignmentTo(node) declaredInScope(scp) {
    def name = node.nameString
    def kind = scp.kind(name)
    var more := ""
    def suggestions = []
    if (scp.elementLines.contains(name)) then {
        more := " on line {scp.elementLines.get(name)}"
    }
    if (kind == k.defdec) then {
        if (reserved.contains(name)) then {
            errormessages.syntaxError("'{name}' is a reserved name and "
                ++ "cannot be re-bound.") atLine(node.line)
        }
        if (scp.elementTokens.contains(name)) then {
            def tok = scp.elementTokens.get(name)
            def sugg = errormessages.suggestion.new
            var eq := tok
            while {(eq.kind != "op") || (eq.value != "=")} do {
                eq := eq.next
            }
            sugg.replaceToken(eq)with(":=")
            sugg.replaceToken(tok)with("var")
            suggestions.push(sugg)
        }
        errormessages.syntaxError("'{name}' cannot be changed "
            ++ "because it was declared with 'def'{more}. "
            ++ "To make it a variable, use 'var' in the declaration")
            atLine(node.line) withSuggestions(suggestions)
    } elseif { kind == k.typedec } then {
        errormessages.syntaxError("'{name}' cannot be re-bound "
            ++ "because it is declared as a type{more}.")
            atLine(node.line)
    } elseif { kind.isParameter } then {
        errormessages.syntaxError("'{name}' cannot be re-bound "
            ++ "because it is declared as a parameter{more}.")
            atLine(node.line)
    } elseif { kind == k.methdec } then {
        errormessages.syntaxError("'{name}' cannot be re-bound "
            ++ "because it is declared as a method{more}.")
            atLine(node.line)
    }
}

method resolveIdentifiers(topNode) {
    // Recursively replace bare identifiers with their fully-qualified
    // equivalents.  Creates and returns a new AST

    topNode.map { node, as ->
        if ( node.isAppliedOccurenceOfIdentifier ) then {
            rewriteIdentifier(node) ancestors(as)
            // TODO — opNodes don't contain identifiers!
        } elseif { node.isInherits } then {
            transformInherits(node) ancestors(as)
        } elseif { node.isBind } then {
            transformBind(node) ancestors(as)
        } else {
            node
        } 
    } ancestors (ast.ancestorChain.empty)
}

method processGCT(gct, importedModuleScope) {
    gct.at "classes" ifAbsent {emptySequence}.do { c ->
        def cmeths = []
        def constrs = gct.at "constructors-of:{c}"
        def classScope = newScopeIn(importedModuleScope) kind "class"
        for (constrs) do { constr ->
            def ns = newScopeIn(importedModuleScope) kind("object")
            classScope.addName(constr)
            classScope.at(constr) putScope(ns)
            gct.at "methods-of:{c}.{constr}".do { mn ->
                ns.addName(mn)
            }
        }
        importedModuleScope.addName(c)
        importedModuleScope.at(c) putScope(classScope)
    }
    gct.at "fresh-methods" ifAbsent {emptySequence}.do { c ->
        def objScope = newScopeIn(importedModuleScope) kind "object"
        gct.at "fresh:{c}".do { mn ->
            objScope.addName(mn)
        }
        importedModuleScope.addName(c)
        importedModuleScope.at(c) putScope(objScope)
    }
}

method setupContext(moduleObject) {
    // define the built-in names
    util.setPosition(0, 0)

    builtInsScope.addName "Type" as(k.typedec)
    builtInsScope.addName "Object" as(k.typedec)
    builtInsScope.addName "Unknown" as(k.typedec)
    builtInsScope.addName "String" as(k.typedec)
    builtInsScope.addName "Number" as(k.typedec)
    builtInsScope.addName "Boolean" as(k.typedec)
    builtInsScope.addName "Block" as(k.typedec)
    builtInsScope.addName "Done" as(k.typedec)
    builtInsScope.addName "done" as(k.defdec)
    builtInsScope.addName "true" as(k.defdec)
    builtInsScope.addName "false" as(k.defdec)
    builtInsScope.addName "super" as(k.defdec)
    builtInsScope.addName "outer" as(k.defdec)
    builtInsScope.addName "readable"
    builtInsScope.addName "writable"
    builtInsScope.addName "public"
    builtInsScope.addName "confidential"
    builtInsScope.addName "override"
    builtInsScope.addName "parent"
    builtInsScope.addName "..." as(k.defdec)

    preludeScope.addName "asString"
    preludeScope.addName "::"
    preludeScope.addName "++"
    preludeScope.addName "=="
    preludeScope.addName "!="
    preludeScope.addName "≠"
    preludeScope.addName "for()do"
    preludeScope.addName "while()do"
    preludeScope.addName "print"
    preludeScope.addName "native()code"
    preludeScope.addName "Exception" as(k.defdec)
    preludeScope.addName "Error" as(k.defdec)
    preludeScope.addName "RuntimeError" as(k.defdec)
    preludeScope.addName "NoSuchMethod" as(k.defdec)
    preludeScope.addName "ProgrammingError" as(k.defdec)
    preludeScope.addName "TypeError" as(k.defdec)
    preludeScope.addName "ResourceException" as(k.defdec)
    preludeScope.addName "EnvironmentException" as(k.defdec)
    preludeScope.addName "π" as(k.defdec)
    preludeScope.addName "infinity" as(k.defdec)
    preludeScope.addName "minigrace"
    preludeScope.addName "_methods"
    preludeScope.addName "PrimitiveArray"
    preludeScope.addName "primitiveArray"
    preludeScope.addName "become"
    preludeScope.addName "unbecome"
    preludeScope.addName "clone"
    preludeScope.addName "inBrowser"
    preludeScope.addName "identical"
    preludeScope.addName "different"
    preludeScope.addName "engine"

    graceObjectScope.addName "=="
    graceObjectScope.addName "!="
    graceObjectScope.addName "≠"
    graceObjectScope.addName "basicAsString"
    graceObjectScope.addName "asString"
    graceObjectScope.addName "asDebugString"
    graceObjectScope.addName "::"
    
    builtInsScope.addName "graceObject"
    builtInsScope.at "graceObject" putScope(graceObjectScope)
    builtInsScope.addName "prelude" as(k.defdec)
    builtInsScope.at "prelude" putScope(preludeScope)
    builtInsScope.addName "_prelude" as(k.defdec)
    builtInsScope.at "_prelude" putScope(preludeScope)

    // Historical - should be removed eventually
    if (!util.extensions.contains("NativePrelude")) then {
        var hadDialect := false
        for (moduleObject.values) do {val->
            if (val.kind == "dialect") then {
                hadDialect := true
                xmodule.checkExternalModule(val)
                def gctDict = xmodule.parseGCT(val.value)
                gctDict.at "public" ifAbsent {emptySequence}.do { mn ->
                    preludeScope.addName(mn)
                }
                gctDict.at "confidential" ifAbsent {emptySequence}.do { mn ->
                    preludeScope.addName(mn)
                }
                processGCT(gctDict, preludeScope)
            }
        }
        if (!hadDialect) then {
            def gctDict = xmodule.parseGCT "StandardPrelude"
            gctDict.at "public" ifAbsent{emptySequence}.do { mn ->
                preludeScope.addName(mn)
            }
            gctDict.at "confidential" ifAbsent {emptySequence}.do { mn ->
                preludeScope.addName(mn)
            }
            processGCT(gctDict, preludeScope)
        }
    }
}
method buildSymbolTableFor(topNode) ancestors(topChain) {
    def symbolTableVis = object {
        inherits ast.baseVisitor

        method visitBind(o) up(as) {
            o.scope := as.parent.scope
            def lValue = o.dest
            if (lValue.kind == "identifier") then {
                lValue.isAssigned := true
            }
            return true
        }
        method visitCall(o) up(as) {
            o.scope := as.parent.scope
            def callee = o.value
            if (callee.kind == "identifier") then {
                callee.inRequest := true
            }
            return true
        }
        method visitBlock(o) up(as) {
            o.scope := newScopeIn(as.parent.scope) kind "block"
            true
        }
        method visitClass(o) up(as) {
            def classNameNode = o.name
            def factoryMeth = o.constructor
            def surroundingScope = as.parent.scope
            checkForReservedName(classNameNode)
            surroundingScope.addNode(classNameNode) as(k.defdec)
            classNameNode.isDeclaredByParent := true
            def outerObjectScope = newScopeIn(surroundingScope) kind "object"
            surroundingScope.at(classNameNode.nameString) putScope(outerObjectScope)
            checkForReservedName(factoryMeth)
            outerObjectScope.addNode(factoryMeth) as(k.methdec)
            factoryMeth.isDeclaredByParent := true
            def factoryScope = newScopeIn(outerObjectScope) kind "method"
            if (o.typeParams != false) then {
                o.typeParams.do { each ->
                    factoryScope.addNode(each) as(k.typeparam)
                    each.isDeclaredByParent := true
                }
            }
            def innerObjectScope = newScopeIn(factoryScope) kind "object"
            outerObjectScope.at(factoryMeth.nameString) putScope(innerObjectScope)
            o.scope := innerObjectScope
            true
        }
        method visitDefDec(o) up(as) {
            o.scope := as.parent.scope
            if (false != o.startToken) then {
                as.parent.scope.elementTokens.put(o.name.nameString, o.startToken)
            }
            true
        }
        method visitIdentifier(o) up(as) {
            var scope := as.parent.scope
            o.scope := scope
            if (o.isBindingOccurrence) then {
                if ((o.isDeclaredByParent.not).andAlso{o.wildcard.not}) then {
                    checkForReservedName(o)
                    def kind = o.declarationKindWithAncestors(as)
                    if (kind.isParameter) then {
                        if (scope.variety == "object") then {
                            // this is a hack for declaring the parameters of the factory
                            // method of a class.  The class's symbol table is that of the
                            // fresh object; the factory method's parameters need to go in
                            // the _enclosing_ scope.
                            scope := scope.parent
                            if (scope.variety != "method") then {
                                ProgrammingError.raise "object scope not in method scope"
                            }
                        }
                    }
                    scope.addNode(o) as (kind)
                }
            } elseif {o.wildcard} then {
                errormessages.syntaxError("'_' cannot be used in an expression")
                    atRange(o.line, o.linePos, o.linePos)
            }
            true
        }
        method visitImport(o) up(as) {
            o.scope := as.parent.scope
            xmodule.checkExternalModule(o)
            def gct = xmodule.parseGCT(o.path)
            def otherModule = newScopeIn(as.parent.scope) kind "module"
            processGCT(gct, otherModule)
            o.scope.at(o.nameString) putScope(otherModule)
            true
        }
        method visitInherits(o) up(as) {
            o.scope := as.parent.scope
            if (as.parent.canInherit.not) then {
                errormessages.syntaxError "inherits statements must be inside an object or class"
                    atRange(o.line, o.linePos, o.linePos + 7)
            }
            if (as.parent.superclass != false) then {
                errormessages.syntaxError ("there can be no more than one inherits " ++
                    "statement in an object; there was a prior inherits statement " ++
                    "on line {as.parent.superclass.line}")
                    atRange(o.line, o.linePos, o.linePos + 7)
            }
            as.parent.superclass := o.value    // value = the expression from inheritsNode
            // cache the inherits expression in the object or class that contains it
            true
        }
        method visitMethod(o) up(as) {
            def surroundingScope = as.parent.scope
            if (surroundingScope.isObjectScope.not) then {
                // This check needs to be here so long as the parser accepts
                // class declarations as statments, rather than as method
                // declarations.  Why does it do so?  Because of the old
                // "dotted" class syntax, wherein a class decl was actually a def.
                errormessages.syntaxError("class declarations are permitted only" ++
                    " inside an object") atRange(o.line, o.linePos, o.linePos + 4)
            }
            def ident = o.value
            checkForReservedName(ident)
            surroundingScope.addNode(ident) as(k.methdec)
            ident.isDeclaredByParent := true
            o.scope := newScopeIn(surroundingScope) kind "method"
            if (o.returnsObject) then { 
                o.isFresh := true
            }
            true
        }
        method visitMethodType(o) up(as) {
            o.scope := newScopeIn(as.parent.scope) kind "methodtype"
            // the scope for the parameters (including the type parameters,
            // if any) of this method.
            true
        }
        method visitObject(o) up(as) {
            def myParent = as.parent
            o.scope := newScopeIn(myParent.scope) kind "object"
            true
        }
        method visitModule(o) up(as) { 
            // the module scope was set before the traversal started
            true 
        }
        method visitTypeDec(o) up(as) {
            def enclosingScope = as.parent.scope
            enclosingScope.addNode(o.name) as(k.typedec)
            o.name.isDeclaredByParent := true
            o.scope := newScopeIn(enclosingScope) kind "typedec"
            // this scope will be the home for any type parameters.
            // If there are no parameters, it won't be used.
            // For now we don't distinguish between type decs and type params
            true
        }
        method visitTypeLiteral(o) up (as) {
            o.scope := newScopeIn(as.parent.scope) kind "type"
            true
        }
        method visitTypeParameters(o) up(as) { o.scope := as.parent.scope ; true }
        method visitIf(o) up(as) { o.scope := as.parent.scope ; true }
        method visitMatchCase(o) up(as) { o.scope := as.parent.scope ; true }
        method visitTryCatch(o) up(as) { o.scope := as.parent.scope ; true }
        method visitSignaturePart(o) up(as) { o.scope := as.parent.scope ; true }
        method visitArray(o) up(as) { o.scope := as.parent.scope ; true }
        method visitMember(o) up(as) { o.scope := as.parent.scope ; true }
        method visitGeneric(o) up(as) { o.scope := as.parent.scope ; true }
        method visitString(o) up(as) { o.scope := as.parent.scope ; true }
        method visitNum(o) up(as) { o.scope := as.parent.scope ; true }
        method visitOp(o) up(as) { o.scope := as.parent.scope ; true }
        method visitIndex(o) up(as) { o.scope := as.parent.scope ; true }
        method visitVarDec(o) up(as) { o.scope := as.parent.scope ; true }
        method visitReturn(o) up(as) { o.scope := as.parent.scope ; true }
        method visitDialect(o) up(as) { o.scope := as.parent.scope ; true }
        method visitBlank(o) up(as) { o.scope := as.parent.scope ; true }
        method visitCommentNode(o) up(as) { o.scope := as.parent.scope ; true }
    }   // end of symbolTableVis
    

    def inheritanceVis = object {
        inherits ast.baseVisitor
        method visitClass(o) up (as) {
            collectInheritedNames(o)
            true
        }
        method visitObject(o) up (as) {
            collectInheritedNames(o)
            true
        }
        method visitModule(o) up (as) {
            collectInheritedNames(o)
            true
        }
        method visitDefDec(o) up (as) {
            if (o.returnsObject) then {
                o.scope.at(o.nameString)
                    putScope(o.returnedObjectScope)
            }
            true
        }
        method visitMethod(o) up (as) {
            if (o.returnsObject) then {
                as.parent.scope.at(o.nameString)
                    putScope(o.returnedObjectScope)
            }
            true
        }
    }

    topNode.accept(symbolTableVis) from(topChain)
    topNode.accept(inheritanceVis) from(topChain)
}

method collectInheritedNames(node) {
    // node is an object or class; put the names that it inherits into its scope.
    // In the process, checks for a cycle in the inheritance chain.
    def nodeScope = node.scope
    if (nodeScope.inheritedNames == completed) then { 
        return
    }
    if (nodeScope.inheritedNames == inProgress) then {
        errormessages.syntaxError "cyclic inheritance"
            atRange(node.line, node.linePos, node.linePos)
    }
    var superScope
    nodeScope.inheritedNames := inProgress
    if (node.superclass == false) then { 
        superScope := graceObjectScope
    } else {
        superScope := nodeScope.scopeReferencedBy(node.superclass)
        // If superScope is the universal scope, then we have no information
        // about the inherited attributes
        if (superScope.isUniversal.not) then {
            if (superScope.node != ast.nullNode) then {
                // superScope.node == nullNode when superScope describes 
                // an imported module.
                collectInheritedNames(superScope.node)
            }
        }
    }
    superScope.elements.keysDo { each ->
        if (each != "self") then {
            nodeScope.addName(each) as(k.inherited)
        }
    }
    nodeScope.inheritedNames := completed
}

method transformBind(bindNode) ancestors(as) {
    // bindNode is (a shallow copy of) a bindNode.  If it is 
    // binding a "member", transform it into a
    // a request on a setter method
    def dest = bindNode.dest
    def currentScope = bindNode.scope
    if ( dest.kind == "member" ) then {
        dest.value := dest.value ++ ":="
        ast.callNode.new(dest,
            ( [ast.callWithPart.request(dest.value) withArgs ( [bindNode.value] ) ] ) )
            scope(currentScope)
    } elseif { dest.kind == "index" } then {
        def imem = ast.memberNode.new("[]:=", dest.value) scope(currentScope)
        ast.callNode.new(imem, [ast.callWithPart.request(imem.value) withArgs( [dest.index, bindNode.value] )  scope(currentScope)])
                        scope(currentScope)
    } else {
        bindNode
    }
}


method transformInherits(inhNode) ancestors(as) {
    // inhNode is (a shallow copy of) an inheritsNode.  Transform it to deal
    // with superobject initialization and inherited names, including
    // inheritance modifiers
    def superObject = inhNode.value
    def currentScope = inhNode.scope
    if (currentScope.isObjectScope.not) then {
        errormessages.syntaxError "inherits statements must be directly inside an object"
                    atRange(inhNode.line, inhNode.linePos, inhNode.linePos + 7)
    }
    if (superObject.isAppliedOccurenceOfIdentifier) then {
        // this deals with "inherits true" etc.
        def definingScope = currentScope.thatDefines(superObject.nameString)
        if (definingScope.variety == "built-in") then { return inhNode }
    }
    def superScope = currentScope.scopeReferencedBy(superObject)
    if (inhNode.inheritsFromCall) then {
        var superCall := inhNode.value
        superCall.with.push(ast.callWithPart.request "object" 
            withArgs ( [ast.identifierNode.new("self", false) scope(currentScope)] ))
        def newmem = ast.memberNode.new(superCall.value.value ++ "()object",
            superCall.value.target
        ) scope(currentScope)
        def newcall = ast.callNode.new(newmem, superCall.with) scope(currentScope)
        inhNode.value := newcall
    } elseif {inhNode.inheritsFromMember} then {
        def newmem = ast.memberNode.new(inhNode.value.value ++ "()object",
            inhNode.value.in
        )
        def newcall = ast.callNode.new(newmem, [
            ast.callWithPart.request(inhNode.value.value) withArgs( [] ) scope(currentScope),
            ast.callWithPart.request "object" withArgs (
                [ast.identifierNode.new("self", false) scope(currentScope)]) scope(currentScope)
            ]
        ) scope(currentScope)
        inhNode.value := newcall
    } elseif {! util.extensions.contains "ObjectInheritance"} then {
        errormessages.syntaxError "inheritance must be from a freshly-created object"
            atRange(inhNode.line, superObject.linePos,
                superObject.linePos + superObject.nameString.size - 1)
    }
    superScope.elements.keysDo { each ->
        inhNode.providedNames.add(each)
    }
    inhNode.aliases.do { a ->
        if (superScope.contains(a.oldName.nameString)) then {
            inhNode.providedNames.add(a.newName.nameString)
        } else {
            errormessages.syntaxError "can't define alias for {a.oldName.nameString} because it is not present in the inherited object"
                atRange(a.oldName.line, a.oldName.linePos, a.oldName.linePos + a.oldName.nameString.size - 1)
        }
    }
    inhNode.exclusions.do { exId ->
        inhNode.providedNames.remove(exId.nameString) ifAbsent {
            errormessages.syntaxError "can't exclude {exId.nameString} because it is not present in the inherited object" 
                atRange(exId.line, exId.linePos, exId.linePos + exId.nameString.size - 1)
        }
    }
    inhNode.providedNames.filter { each -> each != "self" }.do { each ->
        currentScope.addName(each) as(k.inherited)
    }
    inhNode
}

method rewriteMatches(topNode) {
    topNode.map { node, as ->
        if (node.isMatchingBlock) then {
            rewritematchblock(node)
        } else {
            node
        }
    } ancestors (ast.ancestorChain.empty)
}

method resolve(moduleObject) {
    util.log_verbose "rewriting tree."
    setupContext(moduleObject)
    util.setPosition(0, 0)
    moduleObject.scope := moduleScope
    def preludeObject = ast.moduleNode.body([moduleObject]) 
        named "prelude" scope (preludeScope)
    def preludeChain = ast.ancestorChain.with(preludeObject)

    def patternMatchModule = rewriteMatches(moduleObject)
    util.log_verbose "pattern-match rewriting done."

    if (util.target == "patterns") then {
        util.outprint "====================================="
        util.outprint "module after pattern-match re-writing"
        util.outprint "====================================="
        util.outprint(patternMatchModule.pretty(0))
        util.log_verbose "done"
        sys.exit(0)
    }

    buildSymbolTableFor(patternMatchModule) ancestors(preludeChain)
    util.log_verbose "symbol tables built."

    if (util.target == "symbols") then {
        util.outprint "====================================="
        util.outprint "module with symbol tables"
        util.outprint "====================================="
        util.outprint "top-level"
        util.outprint "Universal scope = {universalScope.asDebugString}"
        patternMatchModule.scope.do { each ->
            util.outprint (each.asString)
            util.outprint (each.elementScopesAsString)
            util.outprint "----------------"
        }
        util.outprint(patternMatchModule.pretty(0))
        util.log_verbose "done"
        sys.exit(0)
    }
    resolveIdentifiers(patternMatchModule)
}



