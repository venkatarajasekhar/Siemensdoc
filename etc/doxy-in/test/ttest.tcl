#% @file
#% @brief this is the file description

#% @brief
#% something desc für istcl85.
#% @details
#% bla bla
#% @author und weiter gehts
#% @author thomas2 perschak2
#% @bug bug1
#% @todo do something new here
#% @code
#% > linsert {a b c} 9 3
proc istcl85 {} {
    return [expr {$::tcl_version == "8.5"} ? 1 : 0]
}

#% beschreibung von abc.
#% @copyright (c) by Siemens AG Oesterreich 2011
#% @author thomas perschak
#% @author thomas2 perschak2
#% und der andere
#% @details hello world
proc abc {} {
    #%ProcedureRange
    set range(-priority) {-minmax 0:10}
    set range(-break) {-values {yes y no n}}
    #%ProcedureArgs
    set options(-script) {}
    set options(-priority) $::SCOE_CONFIG(priority.GUI)
    set options(-break) yes
    #%EndArgs
    set something d
}

#% @namespace g
#% @brief empty

#% @namespace thread
#% @brief This namespace is support for threaded routines and objects
namespace eval ::g:thread {
    variable mainThreads  ;#% description of variable
    variable threadResults
    variable threadProcs
}

#% store the global thread ids - this is temporary as long as we havn't separated the gui from the rest
#% @details bla bla bla bla
#% @author thomas perschak
proc ::g:thread::setMainThreads {id tid} {
    variable mainThreads
    set mainThreads($id) $tid
}

