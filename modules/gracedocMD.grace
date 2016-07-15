import "ast" as ast
import "parser" as parser
import "lexer" as lexer
import "io" as io
import "sys" as sys

def settings = object {
    var inputdir:String is public := ""
    var outputdir:String is public := ""
    var verbosity:Number is public := 0
    var publicOnly:Boolean is public := false
    def version:Number is public = 1.1
}

//Markdown styling codewords
def code = "code"
def plain = "plaintext"
def heading = "heading"
def bold = "bold"
def italic = "italic"
def baseUrl = "/grace-documentation/" //NOTE: This must be changed for each different site
                                        //    being built!
def classList = "classList"
def typeList = "typeList"


method parseArguments {
    def args = sys.argv
    if (args.size > 1) then {
        def indices = args.indices
        var skip := true
        for (indices) do { i ->
            def arg = args.at(i)
            if (arg.at(1)=="-") then {
                match (arg)
                    case { "-i" ->
                        if (args.size < (i+1)) then {
                            io.error.write "gracedoc: -i requires an argument.\n"
                            sys.exit(1)
                        }
                        skip := true
                        settings.inputdir := args.at(i+1)
                    } case { "-o" ->
                        if (args.size < (i+1)) then {
                            io.error.write "gracedoc: -o requires an argument.\n"
                            sys.exit(1)
                        }
                        skip := true
                        settings.outputdir := args.at(i+1)
                    } case { "-v" ->
                        if (args.size < (i+1)) then {
                            io.error.write "gracedoc: -v requires an argument.\n"
                            sys.exit(1)
                        }
                        skip := true
                        settings.verbosity := args.at(i+1).asNumber
                    } case { "--publiconly" ->
                        settings.publicOnly := true
                    } case { "--help" ->
                        print "Usage: {args.at(1)} -i <path> -o <path> [-v <level>] [--help] [--publiconly]"
                        print "  -i <path>      The directory to process (contains .grace files)"
                        print "  -o <path>      The directory to contain the generated HTML files"
                        print "  [-v <level>]   Optional. Level of detail in output (0 = none, 1 = some, 2 = all); default is 0"
                        print "  [--publiconly] Optional. If set, only public methods are documented and public "
                        print "                 variables are listed as methods. Default is off."
                        print "  [--help]       Optional. Print this usage information."
                    } case { _ ->
                        io.error.write "gracedoc: Invalid argument {arg}.\n"
                    }
            } else {
                if (skip == true) then {
                    skip := false
                } else {
                    io.error.write "gracedoc: Invalid argument {arg}. Arguments must start with a -.\n"
                    sys.exit(1)
                }
            }
        }
        if ((settings.inputdir=="") || (settings.outputdir=="")) then {
            io.error.write "gracedoc: Both the -i and -o arguments are required.\n"
            sys.exit(1)
        }
    } else {
        io.error.write "gracedoc: Both the -i and -o arguments are required.\n"
        sys.exit(1)
    }
}

type Section = type {
    md -> String
    isEmpty -> Boolean
    insert -> Done
}

//Class for the template that the program uses to create the HTML page
class section.withTemplate(md')andCursorAt(idx) -> Section {
    var md:String is readable := md'
    var hasContent is readable := false
    var cursor:Number is confidential := idx
    var elts is public := dictionary []
    method addElement(n:String)withText(t:String) {
        hasContent := true
        elts.at(n)put(t)
    }
    method insert(t:String) {
        hasContent := true
        def begin = md.substringFrom(1)to(cursor)
        def end = md.substringFrom(cursor+1)to(md.size)
        md := "{begin}{t}{end}"
        cursor := cursor + t.size
    }
    method alphabetize {
        var alpha := elts.keys.sorted
        var numElts := 0
        for (alpha) do { k ->
            var rowClass
            if ((numElts % 2) == 0)
                then { rowClass := "row-even" }
                else { rowClass := "row-odd" }
            elts.at(k)put(elts.at(k).replace("class='placeholder'")
                                        with("class='{rowClass}'"))
            insert(elts.at(k))
            numElts := numElts + 1
        }
    }
}


//Class for other sections without a template
class emptySection.withCursorAt(idx) -> Section {
    var md:String is readable := ""
    var hasContent is readable := false
    var cursor:Number is confidential := idx
    var elts is public := dictionary []
    method addElement(n:String)withText(t:String) {
        hasContent := true
        elts.at(n)put(t)
    }
    method insert(t:String) {
        hasContent := true
        def begin = md.substringFrom(1)to(cursor)
        def end = md.substringFrom(cursor+1)to(md.size)
        md := "{begin}{t}{end}"
        cursor := cursor + t.size
    }
    method alphabetize {
        var alpha := elts.keys.sorted
        var numElts := 0
        for (alpha) do { k ->
            var rowClass
            if ((numElts % 2) == 0)
                then { rowClass := "row-even" }
                else { rowClass := "row-odd" }
            elts.at(k)put(elts.at(k).replace("class='placeholder'")
                                        with("class='{rowClass}'"))
            insert(elts.at(k))
            numElts := numElts + 1
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////

//Parameter class
class Parameter{
     var name:String is public := ""
     var args:String is public := ""

     method insertName(text:String){name := name ++ text}
     method insertArg(text:String){args := args ++ text}
}


//Type to hold the properties of methods or
// other parts of objects
class Property{
     var name:String is public := ""
     var params: Set<Parameter> is readable := set [] //Set of parameters
     var comments:String is public := ""

     method addParam(param:Parameter) {params.add(param)}
}

class sidebarModule{
     var name is public := ""
     var classFiles is public := ""
     var typeFiles is public := ""
}

//Class to generate sidebar file...
class sidebarFileGenerator
{
     var fileOut:String := "entries:\n- title: Sidebar\n  product: Documentation\n  version: 1.0\n  folders:\n\n"
     var folderIndent := 2
     var fileIndent := 4
     var classFiles:String := ""
     var typeFiles:String := ""
     var modSet := false
     var inSubFolder := true
     var contentExistsInFolder := false
     var moduleList: Dictionary<sidebarModule> := dictionary []


     //Add to a specific list output
     method add(string:String)toList(aList:String)inModule(modName:String)
     {
          var mod:sidebarModule

          //Try to find the mod in the mooduleList first
          if(moduleList.containsKey(modName))then{
               mod := moduleList.at(modName)
          } else {
               //Create and name the mod
               mod := sidebarModule
               mod.name := modName

               //Store the module in the dictionary
               moduleList.at(modName)put(mod)
          }

          if(aList == classList) then
          {
               mod.classFiles := mod.classFiles ++ string
               //classFiles := classFiles ++ string;
          }
          elseif(aList == typeList) then
          {
               mod.typeFiles := mod.typeFiles ++ string
               //typeFiles := typeFiles ++ string;
          }
          else
          {
               fileOut := fileOut ++ string;
          }
     }

     //Sets the module name and overarching sidebar
     method setModule(name:String)
     {
          //Add the main folder for the module...
          addFolder(name)

          //Set mod flag to true
          modSet := true
     }

     //Add to main output
     method add(string:String)
     {
          fileOut := fileOut ++ string;
     }

     //Adds a folder to the sidebar
     method addFolder(title:String)
     {
          add("\n")
          add("  - title: \"{title}\"\n")
          add("    output: web, pdf\n")
          add("    folderitems:\n")

          //Set the sub folder flag to track indent
          inSubFolder := false
          contentExistsInFolder := false
     }

     //Signals that sub-folders will follow
     method signalSubfolders
     {
          //Check for content... if no content add a blank one
          if(!contentExistsInFolder)  then {addFile("")withLink("404")toList("---")inModule("-none-")}

          //Add the subforlder signal
          add("      subfolders:\n")
     }

     //Adds a subfolder to the sidebar
     method addSubFolder(title:String)
     {
          //Check if we are NOT in subfolder mode... then signal sub-folder start
          if(!inSubFolder) then {signalSubfolders}

          add("\n")
          add("      - title: \"{title}\"\n")
          add("        output: web, pdf\n")
          add("        subfolderitems:\n")

          //Set the sub folder flags to track indent
          inSubFolder := true
          contentExistsInFolder := false
     }

     //Adds a file to the sidebar
     method addFile(title:String)withLink(link:String)toList(aList:String)inModule(modName:String)
     {
          if(inSubFolder) then
          {
               add("\n")toList(aList)inModule(modName)
               add("        - title: \"{title}\"\n")toList(aList)inModule(modName)
               add("          url: /{link}/\n")toList(aList)inModule(modName)
               add("          output: web \n")toList(aList)inModule(modName)
          }
          else
          {
               add("\n")toList(aList)inModule(modName)
               add("    - title: \"{title}\"\n")toList(aList)inModule(modName)
               add("      url: /{link}/\n")toList(aList)inModule(modName)
               add("      output: web \n")toList(aList)inModule(modName)
          }

          contentExistsInFolder := true
     }

     method generate(module:String)
     {
          if (settings.verbosity > 0) then { print "Generating Sidebar... ({sys.elapsedTime})" }
          if(!modSet) then { setModule("Main-1")}; //Just in case setModule was not already called,
                                             // which it should have been

          var mod:sidebarModule := moduleList.at(module)

          //Generate Sub-Folders and then add Files
          addSubFolder("Classes")
          fileOut := fileOut ++ mod.classFiles

          addSubFolder("Types")
          fileOut := fileOut ++ mod.typeFiles

          var out := io.open("{settings.outputdir}/grace-doc-sidebar.yml", "w")
          out.write(fileOut)
          out.close
     }
}

//Class for a markdown writer object
class markdownWriter
{
     var definition: String is readable := ""
     var description: String is readable := ""
     var propSet: Set<Property> is readable := set [] //Set of propeties
     var bin: String is readable := ""
     var currentMode: String := plain

     //Method to add text to definition
     method insertDef(text:String)
     {
          definition := definition ++ text
          print "\n\n Inserted to definition"
     }

     //Method to add text to description
     method insertDesc(text:String)
     {
          description := description ++ text
          print "\n\n Inserted to description"
     }

     //Adds a propety to the set contained in this obj
     method addProp(aTitle:String)withDesc(desc:String)
     {
          //Create the property
          var newProp := Property

          //Set the values
          newProp.title := aTitle;
          newProp.description := desc;

          //Add it to the set
          propSet.add(newProp);

     }
////////////////////////////////////////////////////////

     //For encapsulating code
     method changeMode(newMode:String)
     {
          //Change to code writing
          if((newMode == code) && (currentMode == plain)) then {bin := bin ++ "`"}
          if((newMode == code) && (currentMode == heading)) then {bin := bin ++ "`"}

          //Change to plain writing
          if((newMode == plain) && (currentMode == code)) then {bin := bin ++ "`"}
          //if((newMode == plain) && (currentMode == heading)) then {bin := bin ++ ""}

          //Change to heading writing
          if((newMode == heading) && (currentMode == code)) then {bin := bin ++ "`\n"}
          if(newMode == heading) then { bin := bin ++ "\n### " }
          //No styling change required from plain formatting

          //Set current mode to new mode
          currentMode := newMode;
     }

     //Add text -- ignore mode
     method addText(string:String){ bin := bin ++ string }

     //Add to the non-structured bin variable
     method addText(string:String)inMode(mode:String)
     {
          //Change formatting mode if needed
          changeMode(mode)

          bin := bin ++ string

          //Add a newline after the heading -- hard to do correctly with changeMode call
          if(mode == heading) then {bin := bin ++ "\n"}
     }

     method addCode(string:String)
     {
          bin := bin ++ "`" ++ string ++ "`"
     }

     method addLink(string:String)
     {
          bin := bin ++ string
     }

     method addHeader(string:String)
     {
          bin := bin ++ string ++ "\n"
     }

     method add(string:String) {bin := bin ++ string}

     method addSpace{bin := bin ++ " "}
     method addColon{bin := bin ++ ":"}
     method addComma{bin := bin ++ ","}
     method addBullet{bin := bin ++ "- "}

     //Newline is special, since we should reset the mode...
     method addNewline
     {
          changeMode(plain)
          bin := bin ++ "  \n"
     }

     //Write out all of the markdown to a string,
     //formatted correctly
     method buildMarkdown -> String
     {
          var temp := "### Definition \n"
          temp := temp ++ definition
          temp := temp ++ "\n\n### Description\n"
          temp := temp ++ description

          print (temp)
          return temp

     }

     //Dumps the current bin variable and clears it
     method dumpBin -> String
     {
          //Reset write mode to create a clean slate
          currentMode := plain;
          var temp := bin;
          bin := "";
          return temp }
}



method trim(c:String) -> String {
    var start := 1
    var end := c.size
    while { c.at(start) == " " } do { start := start + 1 }
    while { c.at(end) == " " } do { end := end - 1 }
    return c.substringFrom(start)to(end)
}

method indent(n:Number) -> String {
    //unrolled for optimization
    if (n==0) then { return "" }
    elseif (n==1) then { return "    " }
    elseif (n==2) then { return "        " }
    elseif (n==3) then { return "            " }
    elseif (n==4) then { return "                " }
    elseif (n==5) then { return "                    " }
    elseif (n==6) then { return "                        " }
    elseif (n==7) then { return "                            " }
    elseif (n==8) then { return "                                " }
    else { return "                                    "}
}


class directoryBuilderForFile(in) outTo (dir) as (pageType) {
    inherits ast.baseVisitor

    var isOnClassPage := false
    var isOnTypePage := false
    if (pageType=="class") then { isOnClassPage := true }
    elseif (pageType=="type") then { isOnTypePage := true }

    def pageName = if (in.endsWith(".grace").not) then { in }
                   else { in.substringFrom(0)to(in.size - 6) }
    def title = if (isOnTypePage) then { "Type: {pageName}" }
                elseif (isOnClassPage) then { "Class: {pageName}" }
                else { "Module: {pageName}" }

    def outdir = if (isOnClassPage || isOnTypePage) then { dir } else { pageName }

    method generate is public {
        var outfile
        if (!io.exists("{settings.outputdir}")) then { io.system("mkdir {settings.outputdir}") }
        if (!io.exists("{settings.outputdir}/{outdir}")) then { io.system("mkdir {settings.outputdir}/{outdir}") }

        //Old Types and Classes separate dirs
        //if (!io.exists("{settings.outputdir}/{outdir}/classes")) then {
          //  io.system("mkdir {settings.outputdir}/{outdir}/classes")
        //}
        //if (!io.exists("{settings.outputdir}/{outdir}/types")) then {
          //  io.system("mkdir {settings.outputdir}/{outdir}/types")
        //}
        //if (isOnClassPage) then {
     //       outfile := io.open("{settings.outputdir}/{outdir}/{pageName}.md", "w")
       // } elseif (isOnTypePage) then {
     //       outfile := io.open("{settings.outputdir}/{outdir}/{pageName}.md", "w")
       // } else {
          //  outfile := io.open("{settings.outputdir}/{outdir}/{pageName}.md", "w")
     //   }

        outfile := io.open("{settings.outputdir}/{outdir}/{pageName}.md", "w")
        outfile.write("TEMPORARY")
        outfile.close

        if (!isOnClassPage && !isOnTypePage) then {
            // Rebuild the modules list with contents
            var out := "---\n"
            out := out ++ "title: \"{title}\"\n"
            out := out ++ "keywords: mydoc\n"
            out := out ++ "sidebar: grace-doc-sidebar\n"
            out := out ++ "toc: false"
            out := out ++ "permalink: /drawingCanvas/\n"
            out := out ++ "folder: grace-docs\n"
            out := out ++ "---\n"

            var modules := io.listdir(settings.outputdir)
            def modit = modules.iterator
            while {modit.hasNext} do {
                var mod := modit.next
                if ((mod.startsWith(".")==false) && (!mod.endsWith(".css")) && (!mod.endsWith(".js")) && (mod != "index.md") && (mod != "modules.md") && (mod != "404.md") && (mod != "inputs")) then {
                    out := out ++ "<li><span class='arrow-button-toggle' id='arrow-button-{mod}' onclick=\"toggleContents('{mod}');\">&#9654;</span><a href='{mod}/{mod}.md' target='mainFrame'>{mod}</a></li>"

                    out := out ++ "<div class='contents-list' id='contents-{mod}' style='display:none;'>"

                    out := out ++ "<h6>Types</h6><ul>"
                    var types := io.listdir("{settings.outputdir}/{mod}/types")
                    def typit = types.iterator
                    while {typit.hasNext} do {
                        var typ := typit.next
                        typ := typ.substringFrom(1)to(typ.size - 5)
                        if ((typ.startsWith(".")==false) && (typ != "contents.md")) then {
                            out := out ++ "<li><a href='{mod}/types/{typ}.md' target='mainFrame'>{typ}</a></li>"
                        }
                    }
                    out := out ++ "</ul>"

                    out := out ++ "<h6>Classes</h6><ul>"
                    var clss := io.listdir("{settings.outputdir}/{mod}/classes")
                    def clsit = clss.iterator
                    while {clsit.hasNext} do {
                        var cls := clsit.next
                        cls := cls.substringFrom(1)to(cls.size - 5)
                        if ((cls.startsWith(".")==false) && (cls != "contents.md")) then {
                            out := out ++ "<li><a href='{mod}/classes/{cls}.md' target='mainFrame'>{cls}</a></li>"
                        }
                    }
                    out := out ++ "</ul>"

                    out := out ++ "</div>"
                }
            }
            out := out ++ "</ul></div></body>"
            out := out ++ "</html>"
            var moduleslistfile := io.open("{settings.outputdir}/modules.md", "w")
            moduleslistfile.write(out)
            moduleslistfile.close
        }
    }

    method visitTypeDec(o) -> Boolean {
        if (isOnTypePage == false) then {
            def typeVis = directoryBuilderForFile (o.name.value) outTo (outdir) as "type"
            o.accept(typeVis)
            typeVis.generate
            return false
        }
        return true
    }

    method visitMethod(m) -> Boolean {
        if (m.isClass.not) then { return false }
        if (isOnClassPage == false) then {
            def o = m.body.last
            if (o.superclass != false) then {
                o.superclass.accept(self)
            }
            def classVis = directoryBuilderForFile (o.name) outTo (outdir) as "class"
            o.accept(classVis)
            classVis.generate
            return false
        }
        return true
    }
}


class graceDocVisitor.createFrom(in) outTo (dir) as (pageType) {
    inherits ast.baseVisitor

    var isOnClassPage := false
    var isOnTypePage := false
    if (pageType=="class") then { isOnClassPage := true }
    elseif (pageType=="type") then { isOnTypePage := true }

    def pageName = if (in.endsWith(".grace").not) then { in }
                   else { in.substringFrom(0)to(in.size - 6) }
    def title = if (isOnTypePage) then { "Type: {pageName}" }
                elseif (isOnClassPage) then { "Class: {pageName}" }
                else { "Module: {pageName}" }
    var section1
    var section2
    var section3
    var section4
    var section5
    var footerSection
    var methodtypesSection
    var section6
    var writer := markdownWriter

    def outdir = if (isOnClassPage || isOnTypePage) then { dir } else { pageName }

    //debugging
    if (settings.verbosity > 1) then { print "On {title} - graceDocVisitor created... inMod {outdir} at time: ({sys.elapsedTime})" }

    //Build the template
    buildTemplate


    //LINKS ARE BUILT HERE !! (for both types and classes) MARKDOWN
    //NOTE: If using a different website -- change the baseUrl variable def

    //This method creates and returns the internal page link -- now in markdown
    method getTypeLink(v:String) is confidential {
        def filename = "{v}"
        var out := "[`{v}`]("  //BASEURL defined at top of file  {baseUrl}
        //first, check current module's types directory for filename
        if (io.exists("{settings.outputdir}/{outdir}/{filename}.md")) then {
             out := out ++ "{baseUrl}{filename}"
        //if not found, check imported module directories
        } elseif (io.exists("{settings.outputdir}/imported/types/{filename}.md")) then {
             out := out ++ "{baseUrl}{filename}"
        //if not found, check gracelib types
        } elseif (io.exists("{settings.outputdir}/gracelib/types/{filename}.md")) then {
            out := out ++ "{baseUrl}{filename}"
        } else {
            out := out ++ "\{\{site.baseurl}}/404" //Might want to append real base-url here too
            //print "\nFile NOT FOUND!! --> below"
        }
        //print "\nBaseURL: {baseUrl}\n FileName: {filename}.md"
        out := out ++ ")"
        return out
    }

    method getClassLink(c:String)show(rep:String){
      def filename = "{c}"
      var out := "[`{c}`]("
      //first, check current module's class directory for filename
      if (io.exists("{settings.outputdir}/{outdir}/{filename}.md")) then {
           out := out ++ "{baseUrl}{filename}"
      //if not found, check imported module directories
      } elseif (io.exists("{settings.outputdir}/imported/classes/{filename}.md")) then {
           out := out ++ "{baseUrl}{filename}"
      //if not found, check gracelib classes
      } elseif (io.exists("{settings.outputdir}/gracelib/classes/{filename}.md")) then {
          out := out ++ "{baseUrl}{filename}"
      } else {
          out := out ++ "\{\{site.baseurl}}404" //Might want to append real base-url here too
          //print "\nFile NOT FOUND!! --> below"
      }
      //print "\nBaseURL: {baseUrl}\n FileName: {filename}.md"
      out := out ++ ")"
      return out
    }

    method getClassLink(c:String) is confidential {
        def filename = "{c}.md"
        var out := "[`{c}`]("
        //first, check current module's class directory for filename
        if (io.exists("{settings.outputdir}/{outdir}/classes/{filename}")) then {
            if (isOnClassPage) then {
                out := out ++ "{filename}"
            } elseif (isOnTypePage) then {
                out := out ++ "../classes/{filename}"
            } else {
                out := out ++ "classes/{filename}"
            }
        //if not found, check imported module directories
        } elseif (io.exists("{settings.outputdir}/imported/classes/{filename}")) then {
            if (isOnTypePage || isOnClassPage) then {
                out := out ++ "../../imported/classes/{filename}"
            } else {
                out := out ++ "../imported/classes/{filename}"
            }
        //if not found, check gracelib classes
        } elseif (io.exists("{settings.outputdir}/gracelib/classes/{filename}")) then {
            if (isOnTypePage || isOnClassPage) then {
                out := out ++ "../../gracelib/classes/{filename}"
            } else {
                out := out ++ "../gracelib/classes/{filename}"
            }
        } else {
            var dots := ""
            if (isOnClassPage || isOnTypePage) then {
                dots := "../../"
            } else {
                dots := "../"
            }
            out := out ++ "{dots}404.md"
        }
        out := out ++ ")"
        return out
    }

    method buildTemplate is confidential {
        var cursor := 0
        var out := "---\n"
        var classIndex := 0
        var typeIndex := 0
        var localWriter := markdownWriter

        //Create the permalink for linking
        //need to filter out "Class:" and "Type: "
        var permalink:String := "{title}"

        //Remove the class/type declaration
        permalink := permalink.replace("Class:")with("")
        permalink := permalink.replace("Type:")with("")

        //Remove all spaces from link name
        permalink := permalink.replace(" ")with("")

        //Create the output for the header
        out := out ++ "title: \"{title}\"\n"
        out := out ++ "keywords: mydoc\n"
        out := out ++ "sidebar: grace-doc-sidebar\n"
        out := out ++ "toc: false\n"
        out := out ++ "permalink: /{permalink}/\n"
        out := out ++ "folder: grace-docs\n"
        out := out ++ "---\n"

        //Add the file to the sidebar
        if(title.contains("Class:"))then
        {
             sidebarGen.addFile(title)withLink(permalink)toList(classList)inModule(outdir)
        }
        elseif(title.contains("Type:"))then
        {
             sidebarGen.addFile(title)withLink(permalink)toList(typeList)inModule(outdir)
        }

        //If on a class page, then also generate the page header itself...
        if (isOnClassPage) then
        {
             localWriter.addText("Definition")inMode(heading)
             localWriter.addText(title)inMode(plain)
             localWriter.addNewline
             localWriter.addText("Description")inMode(heading)
             localWriter.addText("Not currently available...")inMode(plain)
             localWriter.addNewline
             localWriter.addText("Properties")inMode(heading)
             localWriter.addNewline

             //Add writer to output...
             out := out ++ localWriter.dumpBin
        }

        //If it is a class overview page...
        if (!isOnClassPage && !isOnTypePage) then
        {
             localWriter.addText("Methods")inMode(heading)
             localWriter.addNewline

             //Add writer to output...
             out := out ++ localWriter.dumpBin
        }

        ///////////////////////////////////////////////////////////////////

        //This line generates the header for the file. We dont need the commands below to
        //be initialized with a template since this program is generating markdown now, not HTML
        section1 := section.withTemplate(out)andCursorAt(cursor)

        section2 := section.withTemplate("")andCursorAt(cursor)

        cursor := 0
        writer.addText("Types")inMode(heading)
        out := writer.dumpBin
        cursor := out.size

        section3 := section.withTemplate(out)andCursorAt(cursor)

        cursor := 0
        writer.addText("Definitions")inMode(heading)
        out := writer.dumpBin
        cursor := out.size
        section4 := section.withTemplate(out)andCursorAt(cursor)

        section5 := section.withTemplate("")andCursorAt(cursor)

        section6 := section.withTemplate("")andCursorAt(cursor)


        methodtypesSection := section.withTemplate("")andCursorAt(cursor)

        footerSection := section.withTemplate("")andCursorAt(cursor)

        ///////////////////////////////////////////////////////////////////

    }

    //Only called once to build 404 page
    method build404 {
        var out := "---\n"
        out := out ++ "title: \"{title}\"\n"
        out := out ++ "keywords: mydoc\n"
        out := out ++ "sidebar: grace-doc-sidebar\n"
        out := out ++ "toc: false\n"
        out := out ++ "permalink: /404/\n"
        out := out ++ "folder: grace-docs\n"
        out := out ++ "---\n"

        out := out ++ "# 404 - Page 'ot Found  "
        out := out ++ "\n  \n  \nOops! The file for this link appears to be missing! \n"
        out := out ++ "Please naviagte back to your previous page!\"\n"

        var file404 := io.open("{settings.outputdir}/404.md", "w")
        file404.write(out)
        file404.close
    }

    //Sets the module name of the sidebar - allowing all pages to be contained in a div
    method setSidebarName
    {
         sidebarGen.setModule(outdir)
    }

    method buildindex {
        var out := "<!-- generated by Gracedoc, v{settings.version} -- https://github.com/reid47/gracedoc -->\n"
        out := out ++ "<!DOCTYPE html>\n<html lang=\"en\">"
        out := out ++ "<head>"
        out := out ++ "<title>GraceDocs</title>"
        out := out ++ "<link rel=\"stylesheet\" href=\"graceDoc.css\">"
        out := out ++ "</head>"
        out := out ++ "<body>"
        out := out ++ "<iframe id=\"frame-sidebar\" src=\"modules.md\" name=\"moduleFrame\"></iframe>"
        out := out ++ "<iframe id=\"frame-main\" src=\"\" name=\"mainFrame\"></iframe>"
        out := out ++ "</body>"
        out := out ++ "</html>"
        var fileindex := io.open("{settings.outputdir}/index.md", "w")
        fileindex.write(out)
        fileindex.close
    }

    method buildjs {
        var out := ‹function toggleContents(eltid) {
    var elt = document.getElementById('contents-'+eltid)
    var arrow = document.getElementById('arrow-button-'+eltid)
    if (elt.style.display == 'none') {
        elt.style.display = 'block';
        arrow.innerHTML = '&#9660';
    } else {
        elt.style.display = 'none';
        arrow.innerHTML = '&#9654';
    }
}›
        var filejs := io.open("{settings.outputdir}/gracedoc.js", "w")
        filejs.write(out)
        filejs.close
    }

    method buildcss {
         print "CSS Built..."
    }

    //Method that generates all of the output based on the different sections
    method generate is public {
        if (settings.verbosity > 1) then { print "On {title} - starting to assemble HTML ({sys.elapsedTime})" }

        var outfile
        var output := ""
        outfile := io.open("{settings.outputdir}/{outdir}/{pageName}.md", "w")

        //////////////////////////////////
        // Replace this with our object
        //////////////////////////////////


        output := output ++ section1.md
        if (section6.hasContent) then {
            output := output ++ section6.md
        }
        if (section4.hasContent) then {
            section4.alphabetize
            output := output ++ section4.md
        }
        if (methodtypesSection.hasContent) then {
            methodtypesSection.alphabetize
            output := output ++ methodtypesSection.md
        }
        if (section3.hasContent) then {
            section3.alphabetize
            output := output ++ section3.md
        }
        if (section5.hasContent) then {
            section5.alphabetize
            output := output ++ section5.md
        }
        if (section2.hasContent) then {
            section2.alphabetize
            output := output ++ section2.md
        }
        output := output ++ footerSection.md
        outfile.write(output)
        outfile.close
        if (settings.verbosity > 1) then { print "On {title} - file written ({sys.elapsedTime})" }
    }

    // TYPE LISTER
    //This is the type compiler that lists all of the variables and methods
    //that a type would have
    //NOTE: Called for every method as an individual function call
    method visitMethodType(o) -> Boolean {
        if (isOnTypePage) then {
            writer.addBullet
            for (o.signature) do { part ->
                writer.addText(part.name)inMode(code)
                writer.addSpace
                if (part.params.size > 0) then {
                    writer.addText("(")inMode(code)
                    for (part.params) do { param ->
                        if (param.dtype != false) then {
                            writer.addText(param.nameString)inMode(code)
                            writer.addColon
                            writer.addSpace
                            if (param.dtype.kind == "identifier") then {
                                writer.addText(getTypeLink(param.dtype.value))inMode(plain)
                                //writer.addSpace
                            } elseif (param.dtype.kind == "generic") then {
                                writer.addText(param.dtype.value.value)inMode(code)
                                writer.addSpace
                                param.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain)} separatedBy { writer.addText(",")inMode(code) }
                            }
                        } else {
                            writer.addText(param.nameString)inMode(code)
                            writer.addSpace
                        }
                        if ((part.params.size > 1) && (param != part.params.last)) then {
                            writer.addText(",")inMode(code)
                        }
                    }
                    writer.addText(")")inMode(code)
                }
                //here...
                writer.addSpace
            }
            writer.addText("—> ")inMode(code)

            if (o.rtype != false) then {
                if (o.rtype.kind == "identifier") then {
                    writer.addText(getTypeLink(o.rtype.value))inMode(plain)
                } elseif (o.rtype.kind == "generic") then {
                    writer.addText(getTypeLink(o.rtype.value.value))inMode(plain)
                    o.rtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma}
                }
            } else {
                writer.addText("Done")inMode(code)
            }
            //Two spaces for markdown newline added here!
            writer.addText("  \n")inMode(plain)
            writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
            writer.addNewline
            //methodtypesSection.addElement(n)withText(t)
            section6.insert(writer.dumpBin)
            return false
        } else {
            return true
        }
    }

    //TYPE VISITOR -- MAIN INFO ABOUT TYPE
    //Compiles and writes out the main information about a type
    method visitTypeDec(o) -> Boolean {

         //Code is executed if we are on the main page for a class
         //Lists all of the TYPES in the class
        if (isOnTypePage == false) then {
            def n = o.nameString
            //writer.addText("Definition--1")inMode(heading)
            writer.addBullet
            writer.addText("{getTypeLink(o.name.value)}")inMode(plain)
            if (false != o.typeParams) then {
                writer.addText(" -> ")inMode(code)
                for (o.typeParams.params) do { g ->
                    writer.addText(g.nameString)inMode(code)
                    if (g != o.typeParams.params.last) then {writer.addComma}
                }
            }

            writer.addNewline

            def typeVis = graceDocVisitor.createFrom("{o.name.value}")outTo("{outdir}")as("type")
            o.accept(typeVis)
            typeVis.generate

            writer.addText(formatComments(o) rowClass "description" colspan 1)inMode(plain)

            //Write out to the types section
            section3.addElement(n)withText(writer.dumpBin)
            return false

        //Actual writing for types happens here
        } else {
            writer.addText("Definition")inMode(heading)
            writer.addText("{o.name.value} -> ")inMode(code)
            if (false != o.typeParams) then {
                for (o.typeParams.params) do { g->
                    writer.addText(g.nameString)inMode(code)
                    if (g != o.typeParams.params.last) then {writer.addText(", ")inMode(code)}
                }
            }
            writer.addSpace
            var temp := ""
            var ops := list []
            var tps := list []
            var node := o.value

            if (node.kind == "op") then {
                while {node.kind == "op"} do {
                    ops.push(node.value)
                    if ((node.left.kind == "identifier") && (node.right.kind == "identifier")) then {
                        temp := "{getTypeLink(node.left.value)} `{ops.pop}` {getTypeLink(node.right.value)}"
                    } elseif (node.right.kind == "identifier") then {
                        tps.push(node.right.value)
                    } elseif (node.left.kind == "identifier") then {
                        temp := "{getTypeLink(node.left.value)} `{ops.pop}`"
                    } elseif (node.left.kind == "member") then {
                        temp := getTypeLink("{node.left.in.value}.{node.left.value}") ++ " `{ops.pop}`"
                    } elseif (node.right.kind == "member") then {
                        tps.push("{node.left.in.value}.{node.left.value}")
                    }
                    node := node.left
                }

                //Add and reset temp
                writer.addText(temp)inMode(plain) //Plain mode needed for linking
                temp := ""

                while {(tps.size > 0) && (ops.size > 0)} do {
                    def p = tps.pop
                    temp := "`{temp} {ops.pop}` {getTypeLink(p.value)}"
                }
                if (ops.size > 0) then {
                    temp := "`{temp} {ops.pop}`"
                }

                temp := temp ++ "`type`"
                writer.addText(temp)inMode(plain)
                writer.addText("\{...added methods below...\}")inMode(code)
            } elseif (node.kind == "typeliteral") then {

                temp := temp ++ "type"
                writer.addText("\{...added methods below...\}")inMode(code)
            } elseif (node.kind == "identifier") then {
                writer.addSpace
                writer.addText(getTypeLink(node.value))inMode(plain)
                if (node.generics != false) then {
                    for (node.generics) do { g->
                        writer.addText(g.value)inMode(code)
                        if (g != node.generics.last) then { writer.add(", ") }
                    }
                }
            } elseif (node.kind == "member") then {
                writer.addText(getTypeLink("{node.in.value}.{node.value}"))inMode(plain)
                if (node.generics != false) then {
                    for (node.generics) do { g->
                        writer.addText(g.value)inMode(code)
                        if (g != node.generics.last) then {writer.addText(", ")inMode(code)}
                    }
                }
            }
            writer.addText("Description")inMode(heading)
            writer.addText(formatComments(o) rowClass "top-box-description" colspan 1)inMode(plain)
            writer.addText("Properties")inMode(heading)
            section6.insert(writer.dumpBin)
            return true
        }

    }

    // Visit some class methods -- on reg class pages
    method visitMethod(o)up(anc) -> Boolean {

        if (settings.publicOnly && o.isConfidential) then { return false }
        if (o.isClass) then {
            return doClassMethod(o)
        }
        writer.addBullet
        for (o.signature) do { part ->
            writer.addText(buildDefChain(anc) ++ part.name)inMode(code)
            //if (part != o.signature.last) then { n := n ++ "()" }
            if (part.params.size > 0) then {
                writer.addText(" ( ")inMode(code)
                for (part.params) do { param ->
                    if (param.dtype != false) then {
                        writer.addText(param.nameString)inMode(code)
                        writer.addColon
                        writer.addSpace
                        if (param.dtype.kind == "identifier") then {
                            writer.addText(getTypeLink(param.dtype.value))inMode(plain)
                        } elseif (param.dtype.kind == "generic") then {
                            writer.addText(getTypeLink(param.dtype.value.value))inMode(plain)
                            param.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma }
                        }
                        //t := t ++ ":<span class='parameter-type'>" ++ getTypeLink(param.dtype.value) ++ "</span>"
                    } else {
                       writer.addText(param.nameString)inMode(code)
                    }
                    if ((part.params.size > 1) && (param != part.params.last)) then {
                        writer.addComma
                    }
                }
                writer.addText(")")inMode(code)
            }
        }
        writer.addSpace
        writer.addText("-> ")inMode(code)
        if (o.dtype != false) then {
            writer.addText(getTypeLink(o.dtype.value))inMode(plain)
        } else {
            writer.addText(getTypeLink("Done"))inMode(plain)
        }
        writer.addNewline
        writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
       // section2.addElement(buildDefChain(anc) ++ n)withText(t)
        //Insert the text into the page
        section6.insert(writer.dumpBin)
        return false
    }



    method buildDefChain(anc) -> String {
      var a := anc
      var s := ""
      while { a.isEmpty.not } do {
          if ("defdec" == a.parent.kind) then {
              s := (a.parent.nameString ++ "." ++ s)
          }
          elseif ("object" != a.parent.kind) then {
              return s
          }
          a := a.forebears
      }
      return s
    }

    //METHOD INFO VISIOR -- called for each method
    //WRITER REPLACEMENT COMPLETED ...
    method doClassMethod(m)up(anc) -> Boolean {
        def o = m.body.last

        //Called for main class page (for each method... )
        if (isOnClassPage == false) then {
            def n = m.nameString //Needed to get class link...
            def link = getClassLink(n) //show(part.name)
            var ch := buildDefChain(anc)
            if (ch != "") then {ch := "`" ++ ch; ch := ch ++ "`";} //Put it in quotes
            def chain = "{ch}{link}"
            writer.addBullet
            if(chain != "") then {writer.addText("{chain}")inMode(plain)} //Add the ancestor methods if there..
            if(!m.signature.isEmpty) then {writer.addText(":: ")inMode(code)}
            m.signature.do { part ->
                if (part.params.size > 0) then {
                    writer.addText(part.name)inMode(code)
                    writer.addText("(")inMode(code)
                    for(part.params) do { param ->
                        if (param.dtype != false) then {
                            writer.addText(param.value)inMode(code)
                            writer.addColon
                            writer.addSpace
                            writer.addText(getTypeLink(param.dtype.nameString))inMode(plain)
                        } else {
                            writer.addText(param.value)inMode(code)
                        }
                        if ((part.params.size > 1) && (param != part.params.last)) then {
                            writer.addComma
                        }
                    }
                    writer.addText(")")inMode(code)
                }
            }

            if (m.dtype != false) then {
                writer.addText(" -> ")inMode(code)
                if (m.dtype.kind == "identifier") then {
                    writer.addText(getTypeLink(m.dtype.value))inMode(plain)
                } elseif (m.dtype.kind == "generic") then {
                    writer.addText(getTypeLink(m.dtype.value.value))inMode(plain)
                    m.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma }
                }
            }

            if(o.superclass != false) then {
                o.superclass.accept(self)
            }

            def classVis = graceDocVisitor.createFrom(n) outTo (outdir) as "class"
            o.accept(classVis)
            classVis.generate
            writer.addNewline
            writer.addNewline
            section6.insert(writer.dumpBin)
            //section5.addElement(buildDefChain(anc) ++ n) withText(t)
            return false

            //IF WE ARE ON A CLASS PAGE
          } else {
            writer.addBullet
            writer.addText(o.name)inMode(code)

            for(m.signature) do { part ->
                writer.addText(part.name)inMode(code)
                if (part.params.size > 0) then {
                    writer.addText(" (")inMode(code)
                    for(part.params) do { param ->
                        if (param.dtype != false) then {
                            writer.addText(param.value)inMode(code)
                            writer.addColon
                            writer.addSpace
                            writer.addText(getTypeLink(param.dtype.value))inMode(plain)
                        } else {
                            writer.addText(param.value)inMode(code)
                            writer.addColon
                        }
                        if ((part.params.size > 1) && (param != part.params.at(part.params.size))) then {
                            writer.addComma
                        }
                    }
                }
                writer.addText(")")inMode(code)
            }

            if (m.dtype != false) then {
                writer.addText(" -> ")inMode(code)
                if (m.dtype.kind == "identifier") then {
                    writer.addText(getTypeLink(m.dtype.value))inMode(plain)
                } elseif (m.dtype.kind == "generic") then {
                    writer.addText(getTypeLink(m.dtype.value.value))inMode(plain)
                    m.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain)} separatedBy { writer.addComma }
                }
            }

            writer.addNewline
            writer.addText(formatComments(o) rowClass "top-box-description" colspan 1)inMode(plain)
            section6.insert(writer.dumpBin)
            return true
        }
    }

    //Visits definitions
    method visitDefDec(o)up(anc) -> Boolean {
        if (isOnClassPage == true) then {
            if (!settings.publicOnly) then {
                def n = o.name.value
                var temp := buildDefChain(anc) ++ n
                writer.addBullet
                if(temp != "")then{writer.addText(buildDefChain(anc) ++ n)inMode(code)}
                writer.addText(" -> ")inMode(code)
                if (o.dtype != false) then {
                    if (o.dtype.kind == "identifier") then {
                        writer.addText(getTypeLink(o.dtype.value))inMode(plain)
                    } elseif (o.dtype.kind == "generic") then {
                        writer.addText(getTypeLink(o.dtype.value.value))inMode(plain)
                        o.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma }
                    }
                }
                writer.addNewline

                writer.addText(formatComments(o) rowClass "description" colspan 3)inMode(plain)
                section4.insert(writer.dumpBin)

            } else {
                //in publicOnly mode, readable defs should show up as getter methods
                if (o.isReadable) then {
                    //FIXME: if isOnTypePage, then ???
                    def n = o.name.value
                    var temp := buildDefChain(anc) ++ n
                    writer.addBullet
                    writer.addText("def ")inMode(code)

                    if(temp != "")then{writer.addText(buildDefChain(anc) ++ n)inMode(code)}
                    writer.addText(" -> ")inMode(code)

                    if (o.dtype != false) then {
                        if (o.dtype.kind == "identifier") then {
                            writer.addText(getTypeLink(o.dtype.value))inMode(plain)
                        } elseif (o.dtype.kind == "generic") then {
                            writer.addText(getTypeLink(o.dtype.value.value))inMode(plain)
                            o.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma }
                        }
                    }
                    writer.addNewline

                    writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
                    section4.insert(writer.dumpBin)

                }
            }
            return false
        } else {
            if (!settings.publicOnly) then {
                def n = buildDefChain(anc) ++ o.name.value
                writer.addBullet
                writer.addText("def {n}")inMode(code)
                writer.addText(" -> ")inMode(code)

                if (o.dtype != false) then {
                    if (o.dtype.kind == "identifier") then {
                        writer.addText(getTypeLink(o.dtype.value))inMode(plain)
                    } elseif (o.dtype.kind == "generic") then {
                        writer.addText(getTypeLink(o.dtype.value.value))inMode(plain)
                        o.dtype.args.do { each -> writer.addText("{each.value}")inMode(code) } separatedBy { writer.addComma }
                    }
                }
                writer.addNewline
                writer.addText(formatComments(o) rowClass "description" colspan 3)inMode(plain)
                section4.insert(writer.dumpBin)

            } else {
                //in publicOnly mode, readable defs should show up as getter methods
                if (o.isReadable) then {
                    writer.addBullet
                    writer.addText("def ")inMode(code)
                    writer.addText("{buildDefChain(anc) ++ o.name.value}")inMode(code)
                    writer.addText(" -> ")inMode(code)
                    def n = o.name.value
                    if (o.dtype != false) then {
                        if (o.dtype.kind == "identifier") then {
                            writer.addText(getTypeLink(o.dtype.value))inMode(plain)
                        } elseif (o.dtype.kind == "generic") then {
                            writer.addText(getTypeLink(o.dtype.value.value))inMode(plain)
                            o.dtype.args.do { each -> writer.addText("{getTypeLink(each.value)}")inMode(plain) } separatedBy { writer.addComma }
                        }
                    }
                    writer.addNewline

                    writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
                    section4.insert(writer.dumpBin)
                }
            }
            return false
        }
    }

    method visitVarDec(o) -> Boolean {
        def n = o.nameString
        if (isOnClassPage == true) then {
            if (!settings.publicOnly) then {
                writer.addBullet
                writer.addText("var ")inMode(code)
                writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                if (o.dtype != false) then {
                    writer.addText(" -> ")inMode(code)
                    writer.addText("{getTypeLink(o.dtype.value)}")inMode(plain)
                }
                writer.addNewline
                writer.addText(formatComments(o) rowClass "description" colspan 3)inMode(plain)
                section4.insert(writer.dumpBin)
            } else {
                if (o.isReadable) then {
                    writer.addBullet
                    writer.addText("var ")inMode(code)
                    writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                    if (o.dtype != false) then {
                         writer.addText(" -> ")inMode(code)
                         writer.addText("{getTypeLink(o.dtype.value)}")inMode(plain)
                    }
                    writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
                    section4.insert(writer.dumpBin)
                }
                if (o.isWritable) then {
                    writer.addBullet
                    writer.addText("var ")inMode(code)
                    writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                    if (o.dtype != false) then {
                        writer.addText(" -> ")inMode(code)
                        writer.addText("(_:{getTypeLink(o.dtype.value)})")inMode(plain)
                    }else{
                        writer.addText("-> Done")inMode(code)
                    }
                    writer.addText("Updates {n}")inMode(code)
                    section4.insert(writer.dumpBin)
                }
            }
            return false
        } else {
            if (!settings.publicOnly) then {
                writer.addBullet
                writer.addText("var ")inMode(code)
                writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                if (o.dtype != false) then {
                     writer.addText(" -> ")inMode(code)
                     writer.addText("{getTypeLink(o.dtype.value)}")inMode(plain)
                }
                writer.addNewline
                writer.addText(formatComments(o) rowClass "description" colspan 3)inMode(plain)
                section4.insert(writer.dumpBin)
            } else {
                if (o.isReadable) then {
                    writer.addBullet
                    writer.addText("var ")inMode(code)
                    writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                    if (o.dtype != false) then {
                         writer.addText(" -> ")inMode(code)
                         writer.addText("{getTypeLink(o.dtype.value)}")inMode(plain)
                    }
                    writer.addNewline
                    writer.addText(formatComments(o) rowClass "description" colspan 2)inMode(plain)
                    section4.insert(writer.dumpBin)
            }
                if (o.isWritable) then {
                    writer.addBullet
                    writer.addText("var ")inMode(code)
                    writer.addText("{buildDefChain(anc)}{o.name.value}")inMode(code)
                    if (o.dtype != false) then {
                       writer.addText(" -> ")inMode(code)
                       writer.addText("(_:{getTypeLink(o.dtype.value)})")inMode(plain)
                    }
                    else{
                       writer.addText("-> Done")inMode(code)
                    }
                    writer.addText("Updates {n}")inMode(code)
                    section4.insert(writer.dumpBin)
                }
            }
            return false
        }
    }

    method visitInherits(o) -> Boolean {
        //if (isOnClassPage) then {

        //} else {
            return true
        //}
    }

}

method formatComments(astNode) rowClass (rowClassName) colspan (n) -> String {
    var t := ""
    if (false != astNode.comments) then {
        t := t ++ astNode.comments.value ++ "\n"
    }
    return t
}

parseArguments

var file
var dbv
var gdv
var modulename
var counter

var allModules := io.listdir(settings.inputdir)
var parsedFiles := dictionary []
var inputWasFound := false
var sidebarGen := sidebarFileGenerator

//LEX AND PARSE ALL INPUT FILES
counter := 1
for (allModules) do { filename ->
    if (filename.endsWith(".grace")) then {
        file := io.open("{settings.inputdir}/{filename}", "r")
        if (settings.verbosity > 0) then { print "On {filename} - lexing... ({sys.elapsedTime})" }
        var tokens := lexer.new.lexfile(file)
        if (settings.verbosity > 0) then { print "On {filename} - done lexing... ({sys.elapsedTime})" }
        if (settings.verbosity > 0) then { print "On {filename} - parsing... ({sys.elapsedTime})" }
        //var values := parser.parse(tokens)
        parsedFiles.at(counter)put(parser.parse(tokens))

        if (settings.verbosity > 0) then { print "On {filename} - done parsing... ({sys.elapsedTime})" }
        counter := counter + 1
        inputWasFound := true
        file.close
    }
}

if (!inputWasFound) then {
    io.error.write "gracedoc: Input error - no Grace files found in the input directory."
    io.error.write "          Either the directory doesn't exist, or it doesn't contain any files."
    io.error.write "          Directories should be named relative to the ./minigrace executable."
    sys.exit(1)
}

//BUILD DIRECTORY STRUCTURE
counter := 1
for (allModules) do { filename ->
    if (filename.endsWith(".grace")) then {
        if (settings.verbosity > 0) then { print "On {filename} - building directories... ({sys.elapsedTime})" }
        modulename := filename.substringFrom(1)to(filename.size - 6)
        def moduleObject = parsedFiles.at(counter)
        dbv := directoryBuilderForFile(filename) outTo (modulename) as "module"
        moduleObject.accept(dbv)
        dbv.generate
        if (settings.verbosity > 0) then { print "On {filename} - directories built... ({sys.elapsedTime})" }
        counter := counter + 1
    }
}

//GENERATE ACTUAL HTML PAGES
counter := 1
//Note: Only generares with modules...
for (allModules) do { filename ->
    if (filename.endsWith(".grace")) then {
        if (settings.verbosity > 0) then { print "On {filename} - generating GraceDocs... ({sys.elapsedTime})" }
        modulename := filename.substringFrom(1)to(filename.size - 6)
        def moduleObject = parsedFiles.at (counter)
        gdv := graceDocVisitor.createFrom(filename) outTo (modulename) as "module"
        moduleObject.accept(gdv)
        gdv.generate
        //gdv.buildindex  -- No Longer needed for markdown...
        //gdv.buildcss
        //gdv.buildjs
        gdv.build404
        gdv.setSidebarName //Set the module of the sidebar for navigation
        sidebarGen.generate(modulename)
        if (settings.verbosity > 0) then { print "On {filename} - done! ({sys.elapsedTime})" }
        if (settings.verbosity > 0) then { print "Sidebar generated:{modulename} at ({sys.elapsedTime})" }
        counter := counter + 1
    }
}
