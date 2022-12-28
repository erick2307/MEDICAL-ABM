;load extensions
extensions [ profiler vid ]
;pathdir --> https://github.com/cstaelin/Pathdir-Extension/releases/tag/v3.0.3
    ;Use --> https://github.com/cstaelin/Pathdir-Extension
;Fuzzy --> https://github.com/luis-r-izquierdo/netlogo-fuzzy-logic-extension/releases/tag/v2.0

__includes [ "input.nls" "setup.nls" "clock.nls" "grid.nls" "space.nls" "emis.nls" "decision.nls" "raydist.nls"]

;define main agents
breed [victims victim]
breed [hospitals hospital]
breed [h-evacuees h-evacuee]
breed [hub-hosps hub-hosp]
breed [SCUs SCU]
breed [fire-stations fire-station]
breed [gather-points gather-point]
breed [doctors doctor]
breed [dmat-teams dmat-team]
breed [hqs hq]
breed [ambulances ambulance]
breed [helis heli]

;define support agents
breed [banners banner]

;define agents variables and parameters
victims-own [ goal health state severeness recovery rescue-unit medicalcenter vic-speed]
;states: 0 not found; 1 found; 2 in-transport; 3 in-hospital; 4 in-hub; 5 in-scu
;health: 0 black; 1-40 red; 41-80 yellow; 81-100 green (units)
;severeness: defines the rate of health reduction 0-1 units/tick critical time: 60min
   ;next time better use this --> https://en.wikipedia.org/wiki/Injury_Severity_Score
hospitals-own [ #beds #drs #dmats #evacuees h-rescue-unit red-patients yellow-patients green-patients gray-patients original-patients damage report-emis? dmat-assigned? needs tsunami?]
;dmat-assigned: true, false
;damage: 0 low; 1 medium; 2 high
h-evacuees-own [ goal health state severeness recovery rescue-unit medicalcenter evac-speed]
;states: 0 in-hospital@tsu; 1 in-transport; 2 in-hospital@no-tsunami
doctors-own [ state duty duty-time dr-speed]
;states: 0 in-hospital; 1 moving; 2 outdoors
;duty: 0 free; 1 on-duty
;duty-time: integer number in minutes
dmat-teams-own [ state goal duty duty-time dmat-speed ]
;states: 0 in-SCU; 1 moving-to-hospital; 2 in-hospital; 3 moving-to-SCU
;duty: 0 free; 1 on-duty
;duty-time: integer number in minutes
hqs-own [ TE-waitlist HWT-waitlist WT-waitlist T-waitlist T-resourcelist D-waitlist D-resourcelist ]
;T-waitlist: list of victims that need to be transported
;T-resourcelist: list of hospitals, ambulances and helis ONLY available
;D-waitlist: list of DMAT teams required (to grasp info to hospitals without EMIS, send to field (these will accelerate SAR) (NOT YET), send to hospitals for staff support)
;D-resourcelist: list of DMAT teams available
;WT-waitlist: list of red patients waiting to be transported from hosp to hub-hospital
;HWT-waitlist: list of red patients waiting to be transported from hub-hospital to SCU
;TE-waitlist: list of evacuees and staff in need of tsunami evacuation by helicopter only.
ambulances-own [ state task goal patient duty duty-time amb-load-unload-time amb-speed ]
;states: 0 in-home; 1 moving-to-victim; 2 loading; 3 moving-to-hospital; 4 unloading; 5 moving-to-home
;states: 0 idle; 1 move
;task: 0 at-home; 1 to-victim; 2 load-unload; 3 to-hospital; 4 to-hub; 5 to-scu
;duty: 0 free; 1 on-duty
helis-own [ state task goal lt-goal patient #trips-left duty duty-time heli-load-unload-time heli-speed ]
;states: 0 idle; 1 move; 2 load; 3 unload
;task: 0 to-home; 11 to-victim; 12 to-scu;
;duty: 0 free; 1 on-duty
hub-hosps-own [ red-patients yellow-patients green-patients gray-patients original-patients #beds #drs #evacuees ]
SCUs-own [ red-patients yellow-patients green-patients gray-patients #beds ]
;other
banners-own [ show? ]

;================================= START UP ======================================
;to startup
;  user-message "Input Parameters can be modified in the 'input.nls' file"
;end

;================================= MAIN ======================================
to go
  profiler:start
  tick
  update-clock
  update-victims
  update-drs
  update-dmats
  update-ambulances
  update-helicopters
  update-hospitals
  update-hub-hosp
  update-SCU
  if movie? [vid:record-view]
  if ticks >= ( hq-set-time * 3600 ) [ update-hq ]
  ;stop condition
  if ticks = time-limit * 3600 [ profiler:stop
    file-open (word "./output/EMIS_" n-sim ".txt")
    file-print profiler:report
    file-close-all
    if movie? [ vid:save-recording (word "./output/movie_" n-sim ".mp4") ]
    stop ]
end

;================================= SUB-MAIN ======================================

to update-victims
  victim-health
  victim-sar
  move-green-to-hospital
end

to update-drs
  ;move-drs-to-hospital
end

to update-hospitals
   update-banners
   update-victim-lists
   update-needs-state
end

to update-hq
  ;Task 1: Support Hospitals
  update-hospital-needs ;based on EMIS data and requests
  sort-needs-by-urgency
  dmat-dispatch-to-hospital-1

  ifelse random-float 100 < 80 ;80% of the time will attend stricken area
  ;Task 2: Manage transport of victims from disaster area to hospitals by ambulances
  [ update-transport-to-hospital-needs ]

  ;Task 3: Manage transport of victims from hospitals to hub and then SCU
  [ update-transport-to-SCU-needs ]

  ;Task 4: Manage transport of victims from inundated hospitals to hub/SCU with min #patients
  update-hospital-tsunami-evacuation
end

to update-hub-hosp
end

to update-dmats
  move-dmats-to-hospital
  dmat-fill-emis
  move-dmats-to-hub
end

to update-ambulances
  move-amb-to-victim
  move-amb-to-hospital
  move-amb-to-hub
  move-amb-to-scu
  move-amb-to-home
  load-unload-ambs
end

to update-helicopters
  move-heli-to-victim
  move-heli-to-scu
  load-unload-heli
end

to update-SCU
end

;******************************* PROCEDURES VICTIMS ***********************************
;states: 0 not found; 1 found; 2 in-transport; 3 in-hospital; 4 in-hub; 5 in-scu

to victim-health ; reducing health every tick, later use distributions from ??
  ask victims with [state != 3 or state != 4]
  [
    set health (health - severeness )
    if health <= 1 [ set color gray ]
    if (health > 1) and (health <= 40) [ set color red ]
    if (health > 41) and (health <= 80) [ set color yellow ]
    if (health > 81) and (health <= 100) [ set color green ]
  ]

  ask victims with [state = 3 or state = 4 ] ;recovery in hospital and hub
  [ if health >= 1 ;not dead
    [ set health (health + recovery )
      if (health > 1) and (health <= 40) [ set color red ]
      if (health > 41) and (health <= 80) [ set color yellow ]
      if (health > 81) and (health <= 100) [ set color green ]
    ]
  ]
end

;-------------------------------------------------------------------------

to victim-sar ;speed of SAR
  ;sardist sets the distribution type, 0: is exponential distribution of time vs victims found
    let pool (sardist 0 ticks) - count victims with [hidden? = false]
    if pool > count victims with [hidden? = true] [ set pool count victims with [hidden? = true] ]
    let order-victims sort victims with [hidden? = true]
    let sar-victims sublist order-victims 0 pool
    foreach sar-victims
    [ i -> ask i
    ;ask n-of pool victims with [hidden? = true]
    ;ask n-of random min (list count victims with [hidden? = true] count victims with [hidden? = false]) victims with [hidden? = true]
    [ set hidden? false
      set state 1
      ;include victims found into T-waitlist of HQ (except gray)
    ask hqs [ if not member? myself T-waitlist and [color] of myself != gray and [color] of myself != green [ set T-waitlist lput myself T-waitlist ] ]
      emis-update
    ]
  ]
end

;-------------------------------------------------------------------------

to move-green-to-hospital
  ask victims with [ color = green and (state = 0 or state = 1)]
    [ ifelse (distance goal < (3 / unit-scale))
      [ file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Victim " who " arrived to hospital alone")
        file-close
        update-patients goal self ]
      [ face goal fd vic-speed ]
    ]
end

;******************************* PROCEDURES DOCTORS ***********************************
;states: true in-hospital; false moving

to move-drs-to-hospital ;moving drs to hospitals
  ask doctors with [ state = 2 and duty = 0 ]
    [ ifelse (distance one-of out-link-neighbors < (3 / unit-scale))
       [ set state 0
         set duty 1
         ask out-link-neighbors [ set #drs #drs + 1 ]
         set hidden? true ]
       [ face one-of out-link-neighbors fd dr-speed ]
    ]
end

;******************************* PROCEDURES HOSPITALS *********************************

to update-banners
  ask banners
  [ ifelse show?
    [ set label (word "id:" [who] of in-link-neighbors
      ", beds:" [#beds] of in-link-neighbors ", drs now:" [#drs] of in-link-neighbors
      ", DMAT now:" [#dmats] of in-link-neighbors  ", evacuees now:[" length first [original-patients] of in-link-neighbors
      "], victims now:" current-#-of-victims-in-hospital in-link-neighbors) ]
    [ set label (word "id:" [who] of in-link-neighbors) ]
  ]
end

to-report current-#-of-victims-in-hospital [ facility ]
  report length first [gray-patients] of facility + length first [red-patients] of facility + length first [yellow-patients] of facility + length first [green-patients] of facility
end

to update-patients [ facility inpatient ]
  if facility != nobody and inpatient != nobody
  [ ask facility
    [ let triage [color] of inpatient
      if triage = 5 [ set gray-patients lput inpatient gray-patients ]
      if triage = 15 [ set red-patients lput inpatient red-patients set #beds #beds - 1 ]
      if triage = 45 [ set yellow-patients lput inpatient yellow-patients set #beds #beds - 1 ]
      if triage = 55 [ set green-patients lput inpatient green-patients  ] ;green patients does not occupy bed! so what effect they have?
    ]
    ask inpatient
    [ set medicalcenter facility
      set rescue-unit nobody
      if is-hospital? medicalcenter [ set state 3 ]
      if is-hub-hosp? medicalcenter [ set state 4 ]
      if is-SCU? medicalcenter [ set state 5 ]
    ]
  ]
end

to update-victim-lists ;to keep patients' health info updated
  ask hospitals [ update-victim-lists-sub ]
  ask hub-hosps [ update-victim-lists-sub ]
  ask SCUs [ update-victim-lists-sub ]
end

to update-victim-lists-sub
    let gypl [ ]
    let rpl [ ]
    let ypl [ ]
    let gpl [ ]
    let x reduce [ [i j] -> sentence i j] (list red-patients yellow-patients green-patients gray-patients)
    foreach x
    [ i -> ask i [ if color = 5 [ set gypl lput self gypl ]
                   if color = 15 [ set rpl lput self rpl ]
                   if color = 45 [ set ypl lput self ypl ]
                   if color = 55 [ set gpl lput self gpl ]
                 ]
    ]
    set gray-patients gypl
    set red-patients rpl
    set yellow-patients ypl
    set green-patients gpl
end

to update-victims-gone [facility outpatient];to keep presence/absence of patients updated
  ask facility
  [ if member? outpatient red-patients [ set red-patients remove outpatient red-patients set #beds #beds + 1 ]
    if member? outpatient yellow-patients [ set yellow-patients remove outpatient yellow-patients set #beds #beds + 1 ]
    if member? outpatient green-patients [ set green-patients remove outpatient green-patients ]
    if member? outpatient gray-patients [ set gray-patients remove outpatient gray-patients ]
    if member? outpatient original-patients [ set original-patients remove outpatient original-patients set #beds #beds + 1 ]
  ]
end

to update-needs-state
  ask hospitals with [ report-emis? = true ]
  [ if needs = "none" [ set color white ]
    if needs = "low" [ set color green ]
    if needs = "medium" [ set color yellow ]
    if needs = "high" [ set color red ]
    if needs = "unknown" [ set color gray ]
  ]
end
;******************************* PROCEDURES HQ ****************************************

;============================== DMAT NEEDS =========================================

to update-hospital-needs
  ;Priority 1 - Hospitals with no info: send 1 DMAT team when no info -> fill emis on duty-time -> back to hq (This task is a priority!)
  ask hospitals with [ not report-emis? and not dmat-assigned? and not tsunami?] [ ask hqs [ if not member? myself D-waitlist [ set D-waitlist lput myself D-waitlist ] ] ]

  ;Priority 2 - Based on #drs vs #victims-in-hospital vs #beds and damage: assess needs of DMAT teams in hospitals
  ;use 'balanced decision tables' (https://en.wikipedia.org/wiki/Decision_table), later may change to fuzzy logic to decide dispatch
  let decision [ ]
  let hosp-list sort hospitals with [report-emis? and not tsunami?] ;only known-to-have-info hospitals and out of inundation area
  foreach hosp-list
  [ x -> ask x [ let info (list #beds (#drs + #dmats) damage dmat-assigned? length red-patients)
                 set decision lput (list x query-table hospital-status info) decision
                 ;set info [ ]
               ]
  ]
  ;add hospitals with needs > "low" to waitlist
  foreach decision
  [ x -> ask first x [ set needs last x
                       if (last x != "none" and last x !="low") or not report-emis?
                          [ ask hqs [ if not member? myself D-waitlist [ set D-waitlist lput myself D-waitlist ] ]
                          ]
                     ]
  ]
end

to sort-needs-by-urgency
  let sorted-list []
  ;adding hospital and needs numbers as a list to a list
  ;show (word "1.D-waitlist: " [D-waitlist] of hqs)
  foreach first [D-waitlist] of hqs
  [ x -> ask x [ set sorted-list lput (list self translate-to-number needs) sorted-list ] ]
  ;show (word "2.sorted-list: " sorted-list)
  ;sort the list based on numbers lower to upper (if "none" or "false" then erase), becuase no need to be in waitlist when no needs and/or info
  set sorted-list filter [ i -> last i != 0 and last i != -1] sorted-list ;when sorting preference for dispatch to info+damaged hospitals instead of no info hospitals
  ;if need to change this strategy, change value -1 to 99 in "unknown" hospitals and sorting will bring them forward.
  ;show (word "3.sorted-list(filtered): " sorted-list)
  set sorted-list sort-by [ [i j] -> last i > last j ] sorted-list
  ;show (word "4.sorted-list(ordered): " sorted-list)
  ;erase needs item to make sorted D-waitlist
  ifelse not empty? sorted-list
    [ ask hqs [ set D-waitlist filter [ i -> is-hospital? i ] reduce sentence sorted-list ] ]
    [ ask hqs [ set D-waitlist sorted-list ] ]
  ;show (word "5.D-waitlist(sorted): " [D-waitlist] of hqs)
end

to dmat-dispatch-to-hospital-1
  if any? dmat-teams with [duty = 0]
  [ let demand length first [D-waitlist] of hqs
    let resource length first [D-resourcelist] of hqs
    if demand > 0
       [ if resource > 0
            [ ;send max possible number of free (duty 0) DMAT teams to fill need
              ifelse (resource - demand >= 0)
                 [ ask n-of demand dmat-teams with [duty = 0] [ dmat-dispatch-to-hospital-2 ]] ; no criteria to select which dmat-team
                 [ ask n-of resource dmat-teams with [duty = 0] [ dmat-dispatch-to-hospital-2 ] ] ;selects only anyone free
            ]
       ]
  ]
end

to dmat-dispatch-to-hospital-2
  set state 1
  set hidden? false
  set goal first one-of [D-waitlist] of hqs
  set duty 1
  file-open (word "./output/EMIS_" n-sim ".txt")
  file-print (word "DMAT " who " has been assigend to attend hospital " [who] of goal )
  file-close
  ask hqs
  [ set D-waitlist remove [goal] of myself D-waitlist
    set D-resourcelist remove myself D-resourcelist
  ]
  ask goal [ set dmat-assigned? true ]
end

;============================== TRANSPORTATION NEEDS =========================================
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; LOCAL TRANSPORT ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-transport-to-hospital-needs
  ;assumption: Always transport by descendent order of severeness (triage conducted by SAR team)
  ;only ambulances transport to hospitlas and helicopters/ambulances to SCU
  ;strategy-1: check min distance amb-vic-hosp
  ask hqs [ ;1. sort T-waitlist by severeness (15=red; 45=yellow) (gray was avoided when found victim - 'victim-sar' process and green can move alone)
    ;-> dead people is not transported in this model unless he/she dies during transportation
    set T-waitlist sort-by [ [i j] -> [color] of i < [color] of j ] T-waitlist
    set T-waitlist filter [ i -> [color] of i != green ] T-waitlist
    ;check resources available
    let amb-res filter [ i -> is-ambulance? i and [duty] of i = 0 ] T-resourcelist
    let ambs turtle-set amb-res ;create agentset from list
    ;pick first victim and assign free amb (closest)
    if length T-waitlist > 0
    [ foreach T-waitlist
      [ vic -> ask vic [ set rescue-unit min-one-of ambs [distance myself]
        ;if no amb available skip and keep waiting
        if rescue-unit != nobody [
          set amb-res remove [rescue-unit] of vic amb-res
          set ambs turtle-set amb-res
          set state 2
          ask hqs [ set T-waitlist remove vic T-waitlist ]
          ask rescue-unit [ set duty 1 set state 1 set task 11 set patient myself set goal patient set hidden? false ]
          ]
        ]
      ]
   ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; WIDE TRANSPORT - STEP 1 (HOSP -> HUB);;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-transport-to-SCU-needs
  ;assume a percentage of red patients in hospitals need wide transport
  let patients-in-hospitals [red-patients] of hospitals with [needs != "none" and not tsunami?]
  if length patients-in-hospitals = 0 [ set patients-in-hospitals [ nobody ]]
  let hosp-transport-needs reduce [ [i j] -> sentence i j] patients-in-hospitals
  let red-total 0
  ifelse hosp-transport-needs = nobody
  [ set red-total -1 ]
  [ set red-total length hosp-transport-needs ]
  if red-total > 0
  [ let wide-need 0.2 ;20% of wide transport need
    let x ceiling (wide-need * red-total) ;integer number of items to pick
    ask hqs
    [ let pre-wt-waitlist sublist hosp-transport-needs 0 x
      foreach pre-wt-waitlist
      [ i -> if [rescue-unit] of i = nobody [ set WT-waitlist remove-duplicates lput i WT-waitlist ] ]
    ]
  ]

  ;arrange for transport from hospitals to hub
  ask hqs [
    ;check resources available
    let amb-res filter [ i -> is-ambulance? i and [duty] of i = 0 ] T-resourcelist
    let ambs turtle-set amb-res ;create agentset from list
    ;pick first victim and assign free amb (closest)
    if length WT-waitlist > 0
    [ foreach WT-waitlist
      [ vic -> ask vic [ set rescue-unit min-one-of ambs [distance myself]
        ;if no amb available skip and keep waiting
        if rescue-unit != nobody [
          set amb-res remove [rescue-unit] of vic amb-res
          set ambs turtle-set amb-res
          set state 2
          ask hqs [ set WT-waitlist remove vic WT-waitlist ]
          ask rescue-unit [ set duty 1 set state 1 set task 21 set patient myself set goal [medicalcenter] of patient set hidden? false ]
        ]
        ]
      ]
    ]
  ]

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; WIDE TRANSPORT - STEP 2 (HUB -> SCU) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;arrange for transport from hub to scu
   ask hqs [
    ;check resources available
    let amb-res filter [ i -> is-ambulance? i and [duty] of i = 0 ] T-resourcelist
    let ambs turtle-set amb-res ;create agentset from list
    let helic-res filter [ i -> is-heli? i and [duty] of i = 0  ] T-resourcelist
    let helics turtle-set helic-res
    ;pick first victim and assign free heli or amb (closest)
    let hub-wide-transport-needs [ ]
    ask hub-hosps [ set hub-wide-transport-needs remove-duplicates reduce [ [i j] -> sentence i j] (list red-patients yellow-patients green-patients gray-patients) ]
    ;Moving everyone?? (red-yellow-green-gray) check!
    foreach hub-wide-transport-needs
    [ i -> if [rescue-unit] of i = nobody [ set HWT-waitlist remove-duplicates lput i HWT-waitlist ] ]
    if length HWT-waitlist > 0
    [ foreach HWT-waitlist
      [ vic -> ask vic [
        set rescue-unit min-one-of helics [distance myself]
        ;if no helic available try ambs otherwise skip and keep waiting
        ifelse rescue-unit != nobody
        [
          set helic-res remove [rescue-unit] of vic helic-res
          set helics turtle-set helic-res
          set state 2
          ask hqs [ set HWT-waitlist remove vic HWT-waitlist ]
          ask rescue-unit [ set duty 1 set state 1 set task 11 set patient myself set #trips-left 1 set goal [medicalcenter] of patient set hidden? false ]
        ]
        [ set rescue-unit min-one-of ambs [distance myself]
          if rescue-unit != nobody
           [
             set amb-res remove [rescue-unit] of vic amb-res
             set ambs turtle-set amb-res
             set state 2
             ask hqs [ set HWT-waitlist remove vic HWT-waitlist ]
             ask rescue-unit [ set duty 1 set state 1 set task 31 set patient myself set goal [medicalcenter] of patient set hidden? false ]
           ]
        ]
        ]
      ]
    ]
  ]
end

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; WIDE TRANSPORT - TSUNAMI EVACUATION ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-hospital-tsunami-evacuation
  ;search for hospitals in tsunami evacuation need
  ;add hosps to waitlist sorted by max number of people to evacuate
  ask hqs
  [
  ;assign helicopter to first hosp in need -> continue until finish evacuation of people (how to count?)
    let helic-res filter [ i -> is-heli? i and [duty] of i = 0  ] T-resourcelist
    let helics turtle-set helic-res

    ;pick first hosp and assign free heli and the evacuee to the heli
    if length TE-waitlist > 0
    [ foreach TE-waitlist
      [ hte -> ask hte [ ;hte = hospital to evacuate
        set h-rescue-unit min-one-of helics [distance myself]
        ;if no helic available try later
        if h-rescue-unit != nobody
        [
          set helic-res remove [h-rescue-unit] of hte helic-res
          set helics turtle-set helic-res
          set needs "unknown"
          set color white
          ask hqs [ set TE-waitlist remove hte TE-waitlist ]
          ask h-rescue-unit
          [
            set duty 1
            set state 1
            set task 11
            set patient first [original-patients] of hte
            set #trips-left length [original-patients] of hte
            set goal hte
            set lt-goal hte
            set hidden? false
          ]
        ]
        ]
      ]
    ]
  ]
end

;******************************* PROCEDURES DMAT TEAMS ****************************************
;states: 0 in-gathering-point; 1 moving-to-hospital; 2 in-hospital; 3 moving-to-Gathering-point

to move-dmats-to-hospital
  ask dmat-teams with [state = 1] [ if goal != nobody
    [ ifelse distance goal < 3 / unit-scale
      [ set state 2
        set hidden? true
        set duty 1
        ifelse [report-emis?] of goal
        [ set duty-time 0
          file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "DMAT " who " arrived to hospital " [who] of goal " staying for support" )
          file-close
        ]
        [ set duty-time (ticks + (random 10 * 60) + 1 ) ;1-10min
          file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "DMAT " who " arrived to hospital " [who] of goal " finishing duty on tick " duty-time )
          file-close
        ]
        ask goal [ set #dmats #dmats + 1 ]
      ]
      [face goal fd dmat-speed ]
    ]
  ]
end

to dmat-fill-emis ;or support health care
  ask dmat-teams with [state = 2]
  [ if duty-time = ticks
    [ set state 3
      file-open (word "./output/EMIS_" n-sim ".txt")
      file-print (word "DMAT " who " finished task, heading to Gathering Point" )
      file-close
      ask goal
        [ set report-emis? true
          set dmat-assigned? false
          set #dmats #dmats - 1
          emis-update
          ask out-link-neighbors [ set show? true ]
          update-banners
        ]
      set goal one-of gather-points
      ask hqs [ if not member? myself D-resourcelist [ set D-resourcelist lput myself D-resourcelist ] ]
      set duty 0
      set duty-time 0
      set hidden? false
  ] ]
end


to move-dmats-to-hub ;back to gathering point or hub?
  ask dmat-teams with [state = 3]
    [ ifelse distance goal < 3 / unit-scale ;max speed is 2.8, better use a higher number to avoid jerking
      [ set state 0
        set hidden? true
        set duty 0
        set duty-time 0
        ask hqs [ if not member? myself D-resourcelist [ set D-resourcelist lput myself D-resourcelist ] ]
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "DMAT " who " arrived to Hub hospital. Waiting for instructions." )
        file-close
      ]
      [face goal fd dmat-speed ]
    ]
end

;******************************* PROCEDURES AMBULANCES ****************************************
;states: 0 idle; 1 move; 2 load; 3 unload
;task: 0 to-home; 11 to-victim; 12 to-hospital (unload); 21 to-hospital (load); 22 to-hub (unload); 31 to-hub (load); 32 to-scu (unload)
;duty: 0 free; 1 on-duty

to move-amb-to-victim
  ask ambulances with [state = 1 and task = 11] ;'move' 'to-victim'
  [ if patient != nobody and goal = patient
    [ ifelse distance patient < 23 / unit-scale
      [ set state 2
        move-to goal
        set duty-time (ticks + amb-load-unload-time )
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " arrived to victim " [who] of patient " finishing loading on tick " duty-time )
        file-close
      ]
      [ face goal fd amb-speed
      ]
    ]
  ]
end

to move-amb-to-hospital
  ask ambulances with [ state = 1 and (task = 12 or task = 21)] ;'move' 'to-hospital'
  [ if goal != nobody
    [ ifelse distance goal < 23 / unit-scale
      [ move-to goal
        set duty-time (ticks + amb-load-unload-time )
        if state = 1 and task = 12
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " arrived to hospital " [who] of goal " finishing unloading on tick " duty-time )
          file-close
          set state 3
        ]
        if state = 1 and task = 21
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " arrived to hospital " [who] of goal " finishing loading on tick " duty-time )
          file-close
          set state 2
        ]
      ]
      [ face goal fd amb-speed
      ]
    ]
  ]
end

to move-amb-to-hub
  ask ambulances with [ state = 1 and (task = 22 or task = 31)]
  [ if goal != nobody
    [ ifelse distance goal < 23 / unit-scale
      [ move-to goal
        set duty-time (ticks + amb-load-unload-time )
        if state = 1 and task = 22
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " arrived to Hub Hospital " [who] of goal " finishing unloading on tick " duty-time )
          file-close
          set state 3
        ]
        if state = 1 and task = 31
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " arrived to Hub Hospital " [who] of goal " finishing loading on tick " duty-time )
          file-close
          set state 2
        ]
      ]
      [ face goal fd amb-speed
        ;if [health] of patient <= 1 [ show "Patient dead in ambulance while transporting!. Leaving in Hub hosp" ] ;this might be repeated when arriving
      ]
    ]
  ]
end

to move-amb-to-scu
  ask ambulances with [state = 1 and task = 32]
  [ if goal != nobody
    [ ifelse distance goal < 23 / unit-scale
      [ set state 3
        move-to goal
        set duty-time (ticks + amb-load-unload-time )
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " arrived to SCU " [who] of goal " finishing unloading on tick " duty-time )
        file-close
      ]
      [ face goal fd amb-speed
        ;if [health] of patient <= 1 [ show "Patient dead in ambulance while transporting!. Leaving in Hub hosp" ] ;this might be repeated when arriving
      ]
    ]
  ]
end

to move-amb-to-home
  ask ambulances with [state = 1 and task = 0]
  [ if goal != nobody
    [ ifelse distance goal < 23 / unit-scale
      [ move-to goal
        set hidden? true
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " arrived home. Waiting for instruction" )
        file-close
        set state 0
        set task 0
        set duty 0
        set duty-time 0
        set goal nobody
        set patient nobody
      ]
      [ face goal fd amb-speed ]
    ]
  ]
end

to load-unload-ambs
  ;loading
  ask ambulances with [state = 2]
  [ if duty-time = ticks
    [ if state = 2 and task = 11 ;victim 'load' in disaster area to be taken 'to-hospital'
      [ ifelse [health] of patient <= 1
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print "patient dead in ambulance while loading!. Leaving patient to Police."
          file-close
          set duty 0
          set duty-time 0
          set state 1
          set task 0
          set goal one-of fire-stations
          set patient nobody
        ]
        [ set state 1
          set task 12
          set goal min-one-of hospitals with [report-emis? = true and not tsunami? and #beds > 0 and damage < 2 ] [distance myself]
          if goal = nobody [ set goal one-of SCUs file-open (word "./output/EMIS_" n-sim ".txt") file-print "moving to SCU, all hospitals full" file-close ] ;if no hospital available trasnport direct to SCU
          ask patient [ move-to [goal] of myself set state 2 ]
          file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " finished loading patient, heading to hospital " [who] of goal  )
          file-close
        ]
      ]

      if state = 2 and task = 21 ;victim 'load' in hospital to be taken 'to-hub'
      [ ifelse [health] of patient <= 1
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print "patient dead in ambulance while loading!. Leaving patient in Hospital"
          file-close
          set duty 0
          set duty-time 0
          set state 1
          set task 0
          set goal one-of fire-stations
          set patient nobody
        ]
        [ update-victims-gone goal patient
          set state 1
          set task 22
          set goal min-one-of hub-hosps [distance myself]
          ask patient [ move-to [goal] of myself set state 2 ]
          file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " finished loading patient, heading to Hub hospital " [who] of goal  )
          file-close
        ]
      ]

      if state = 2 and task = 31
      [ ifelse [health] of patient <= 1
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print "patient dead in ambulance while loading!. Leaving patient in Hub Hospital."
          file-close
          set duty 0
          set duty-time 0
          set state 1
          set task 0
          set goal one-of fire-stations
          set patient nobody
        ]
        [ update-victims-gone goal patient
          set task 32
          set state 1
          set goal min-one-of SCUs [distance myself]
          ask patient [ move-to [goal] of myself set state 2 ]
          file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Ambulance " who " finished loading patient, heading to SCU " [who] of goal  )
          file-close
        ]
      ]
    ]
  ]

  ;unloading
  ask ambulances with [state = 3]
  [ if duty-time = ticks
    [ if task = 12
      [ if [health] of patient <= 1 [ file-open (word "./output/EMIS_" n-sim ".txt")
        file-print "patient dead in ambulance while unloading!. Leaving patient in Hospital"
        file-close ]
        update-patients goal patient
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " finished unloading patient, heading back home.")
        file-close
        set state 1
        set task 0
        set duty 0
        set duty-time 0
        set goal one-of fire-stations
        set patient nobody
      ]

      if task = 22
      [ if [health] of patient <= 1 [ file-open (word "./output/EMIS_" n-sim ".txt")
        file-print "patient dead in ambulance while unloading!. Leaving patient in Hub Hospital"
        file-close ]
        update-patients goal patient
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " finished unloading patient. Waiting for instructions.")
        file-close
        set state 0
        set task 0
        set duty 0
        set duty-time 0
        set goal nobody
        set patient nobody
      ]

      if task = 32
      [ if [health] of patient <= 1 [ file-open (word "./output/EMIS_" n-sim ".txt")
        file-print "patient dead in ambulance while unloading!. Leaving patient in SCU"
        file-close ]
        ask patient [ set state 5 set severeness 0 ] ;total safety
        update-patients goal patient
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Ambulance " who " finished unloading patient, heading back home.")
        file-close
        set state 1
        set task 0
        set duty 0
        set duty-time 0
        set goal one-of fire-stations
        set patient nobody
      ]
    ]
  ]
end

;******************************* PROCEDURES HELICOPTERS ****************************************
;states: 0 idle; 1 move; 2 load; 3 unload
;task: 0 to-home; 11 to-victim; 12 to-scu
;duty: 0 free; 1 on-duty

to move-heli-to-victim ;in hub or tsu-hosp
  ask helis with [state = 1 and task = 11]
  [ if patient != nobody
    [ ifelse distance patient < 45 / unit-scale
      [ set state 2
        move-to patient
        set duty-time (ticks + heli-load-unload-time )
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Helicopter " who " arrived to victim " [who] of patient " finishing loading on tick " duty-time )
        file-close
      ]
      [ face patient fd heli-speed
      ]
    ]
  ]
end

to move-heli-to-scu
  ask helis with [state = 1 and task = 12]
  [ if goal != nobody
    [ ifelse distance goal < 45 / unit-scale
      [ set state 3
        move-to goal
        set duty-time (ticks + heli-load-unload-time )
        file-open (word "./output/EMIS_" n-sim ".txt")
        file-print (word "Helicopter " who " arrived to SCU " [who] of goal " finishing unloading on tick " duty-time )
        file-close
      ]
      [face goal fd heli-speed
      ]
    ]
  ]
end

to load-unload-heli
   ;loading
  ask helis with [state = 2]
  [ if duty-time = ticks
    [ if task = 11
      [ ifelse [health] of patient <= 1
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print "Patient dead in helicopter while loading!. Leaving patient."
          file-close
          ifelse #trips-left > 1
          [ file-open (word "./output/EMIS_" n-sim ".txt")
            file-print "Loading next evacuee in list"
            file-print (word "Helicopter " who " finished loading patient, heading to SCU " [who] of goal  )
            file-close
            update-victims-gone goal patient
            set state 1
            set task 12
            set goal min-one-of SCUs [distance myself]
            ask patient [ move-to [goal] of myself set state 2 ]
          ]
          [ set duty 0
            set state 1
            set task 0
            set goal min-one-of SCUs [distance myself]
            set patient nobody
          ]
        ]
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Helicopter " who " finished loading patient, heading to SCU " [who] of goal  )
          file-close
          update-victims-gone goal patient
          set state 1
          set task 12
          set goal min-one-of SCUs [distance myself]
          ask patient [ move-to [goal] of myself set state 2 ]
        ]
      ]
    ]
  ]

  ;unloading
  ask helis with [state = 3]
  [ if duty-time = ticks
    [ if task = 12
      [ if [health] of patient <= 1 [ file-open (word "./output/EMIS_" n-sim ".txt")
        file-print "Patient dead in helicopter while unloading!. Leaving patient in SCU"
        file-close
        ]
        ask patient [ set state 5 set severeness 0 ] ;total safety
        update-patients goal patient
        ifelse #trips-left > 1
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Helicopter " who " finished unloading patient. Returning for more evacuees")
          file-close
          set state 1
          set task 11
          set duty 1
          set goal lt-goal
          set patient first [original-patients] of lt-goal
          set #trips-left length [original-patients] of lt-goal
        ]
        [ file-open (word "./output/EMIS_" n-sim ".txt")
          file-print (word "Helicopter " who " finished unloading patient. Waiting for instruction")
          file-close
          set state 0
          set task 0
          set duty 0
          set goal nobody
          set patient nobody
          set #trips-left 0
          set lt-goal nobody
          set hidden? true
        ]
      ]

    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
265
10
1073
419
-1
-1
8.0
1
10
1
1
1
0
0
0
1
0
99
0
49
0
0
1
ticks
30.0

OUTPUT
5
421
261
573
13

BUTTON
5
12
78
49
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1074
45
1241
78
Change Date & Time
set-date-and-time
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1074
11
1241
44
GRID (ON/OFF)
grid-switch
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1074
80
1241
113
Show Space 1 Division
divide-space-h
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
1075
184
1243
217
label-heading
label-heading
0
360
207.0
1
1
deg
HORIZONTAL

SLIDER
1075
219
1244
252
label-distance
label-distance
0
50
3.0
1
1
steps
HORIZONTAL

BUTTON
1076
149
1242
182
Adjust Labels
reposition
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1075
115
1242
148
Show Space 2 Division
divide-space-v
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
79
12
148
49
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
6
52
262
239
Search&Rescue
time (sec)
rate of victims
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"High" 1.0 0 -2674135 true "" "ifelse count victims with [color = red] > 0\n [ plot ((count victims with [color = red and hidden? = false])/(count victims with [color = red])) ]\n [ plot 0 ]"
"Medium" 1.0 0 -1184463 true "" "ifelse count victims with [color = yellow] > 0\n [ plot ((count victims with [color = yellow and hidden? = false])/(count victims with [color = yellow])) ]\n [ plot 0 ]"
"Low" 1.0 0 -14439633 true "" "ifelse count victims with [color = green] > 0\n [ plot ((count victims with [color = green and hidden? = false])/(count victims with [color = green])) ]\n [ plot 0 ]"
"Dead" 1.0 0 -7500403 true "" "ifelse count victims with [color = gray] > 0\n [ plot ((count victims with [color = gray and hidden? = false])/(count victims with [color = gray])) ]\n [ plot 0 ]"

BUTTON
6
383
87
416
UPDATE
emis-update
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

MONITOR
1076
254
1173
299
Current Victims
count victims with [hidden? = false]
17
1
11

MONITOR
1175
254
1244
299
Deads
count victims with [color = gray and hidden? = false]
17
1
11

MONITOR
1076
300
1173
345
D-Resources
[length D-resourcelist ] of hqs
17
1
11

MONITOR
1175
301
1244
346
D-Needs
[length D-waitlist] of hqs
17
1
11

BUTTON
88
384
261
417
EXPORT
export-output \"Log.txt\"
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
150
12
261
50
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
5
240
76
285
Red Total
count victims with [color = red]
17
1
11

MONITOR
78
240
175
285
Yellow Total
count victims with [color = yellow]
17
1
11

MONITOR
177
240
262
285
Green Total
count victims with [color = green]
17
1
11

MONITOR
6
288
75
333
Red Now
count victims with [color = red and hidden? = false]
17
1
11

MONITOR
79
288
174
333
Yellow Now
count victims with [color = yellow and hidden? = false]
17
1
11

MONITOR
178
289
262
334
Green Now
count victims with [color = green and hidden? = false]
17
1
11

MONITOR
133
337
261
382
Gray Now
count victims with [color = gray and hidden? = false]
17
1
11

MONITOR
6
337
131
382
Gray Total
count victims with [color = gray]
17
1
11

MONITOR
558
422
1010
467
NIL
hospitals-needs
17
1
11

MONITOR
1076
347
1173
392
T-Resources
[length T-resourcelist ] of hqs
17
1
11

MONITOR
1175
348
1244
393
T-Needs
[length T-waitlist] of hqs
17
1
11

MONITOR
1076
394
1161
439
WT-Needs
[length WT-waitlist] of hqs
17
1
11

MONITOR
1162
394
1244
439
HWT-Needs
[length HWT-waitlist] of hqs
17
1
11

SLIDER
558
470
689
503
#add-dmat
#add-dmat
1
20
11.0
1
1
units
HORIZONTAL

BUTTON
558
505
690
538
Add DMAT teams
add-dmats
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1057
465
1116
510
DSA->H
length first [T-waitlist] of hqs
17
1
11

MONITOR
1117
465
1175
510
H->HH
length first [WT-waitlist] of hqs
17
1
11

MONITOR
1176
465
1247
510
HH->SCU
length first [HWT-waitlist] of hqs
17
1
11

TEXTBOX
1074
445
1246
473
Victims waiting for Transport
11
0.0
1

TEXTBOX
1077
515
1227
571
DSA: Disaster Stricken Area\nH: Hospital\nHH: Hub Hospital\nSCU: Stage Care Unit
11
0.0
1

SLIDER
692
470
851
503
#add-ambulances
#add-ambulances
1
10
5.0
1
1
units
HORIZONTAL

SLIDER
854
469
1010
502
#add-helicopters
#add-helicopters
1
10
2.0
1
1
units
HORIZONTAL

BUTTON
694
505
850
538
Add Ambulances
add-ambulances
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
855
505
1010
538
Add Helicopters
add-helicopters
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
559
540
723
573
Switch ON/OFF labels
let i first [hidden?] of banners\nask banners [ set hidden? not i ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
725
540
1010
585
TE-waitlist
[TE-waitlist] of hqs
17
1
11

SWITCH
264
421
453
454
erase-previous-files?
erase-previous-files?
1
1
-1000

SWITCH
264
454
389
487
from-files?
from-files?
0
1
-1000

SWITCH
263
487
430
520
export-locations?
export-locations?
1
1
-1000

SWITCH
262
520
378
553
replicate?
replicate?
0
1
-1000

BUTTON
380
520
552
553
Switch ON/OFF victims
ask victims[ set hidden? not hidden? ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
460
424
552
484
#dmat
5.0
1
0
Number

SWITCH
261
554
364
587
movie?
movie?
1
1
-1000

@#$#@#$#@
## TO DO LIST

2019.01.18
- green agents transfer nearby red/yellow agents to hospital
- hospital beds 0 then go to other
- do not transport to high damaged hospitals
- consider evacuees to become yellow/red after earthquake
- SAR distribution of time
- Health level function

## WHAT IS IT?

This is a model of Disaster Response Activities including Disaster Medical Assistance Teams (DMAT) and Transportation Rescue Teams (Ambulances and Helicopters). The model simulates the DMAT headquarters (HQ) who gathers the available information of needs and resources to dispatch DMAT teams to gather further information and support Hospitals during the emergency. In addition, ambulances and helicopters are dispatched to transport victims from the disaster stricken area to the hospital or from regular hospitals to hub hospitals and then to SCU areas for wide transport via helicopters.

## HOW IT WORKS

The following agents are present:
1. Headquarters (HQ)
2. SCU
3. Hub Hospital
4. Regular hospitals
5. Doctors
6. DMAT teams
7. Ambulances
8. Helicopters
9. Victims

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

The model considers a unit-scale which represents the equivalence in m of a unit patch.
It is set to 100 by default, then the space where victims are loaded is a rectangular area of 80 x 50 patches, which is 8 x 5 km. (Similar to the size of Ishinomaki)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES
[1] 東日本大震災での DMAT 宮城県調整本部の活動
Activities on DMAT HQ in 3.11 lasted 6 days.
3.11 - only 2 people
3.12 - +1 person and #? nurses and #? staff
later: +3 from Miyagi Pref., +2 from other Pref., #? from Disaster Medical Center,
+2 from national hospital sendai
3.11 (eq+2h) Set HQ (*Actions)
3.12 (12:10) Dr. Heli from Tohoku Univ. Hospital (TUH)
     (16:32) Dr. Heli from Sendai Medical Center
     (16:50) Ishinomaki -> Fukushima Airport -> Haneda Airport
3.13 (5:20) dispatch 1 DMAT team to each hospital
     (5:50) Request of dispatch from 5 hospitals to Fukushima Airp.
     (7:41) TUH (Dr. Heli)
     (9.50) Request DMAT team, 10 teams dispatch
     (10:15) Ishinomaki requests trasnport for 240 patients
     (13:03) Ishinomaki -> Haneda (severe injury patients)
3.14 (2:30) Plan to rescue 240 patients from Ishinomaki 

*Actions:
1. Verify Hospitals disaster condition
2. Number of patients
3. Use EMIS
4. DIS gives estimation 1000 death, 2000 severe patients
5. Set 4 SCU

[2] 東日本大震災で行った長期にわたる大規模転院転所搬送 ─広域医療搬送から病院機能維持のための搬送へ─
Ambulances (43.4％) provided the majority of transport means. Private ambulances and nursing care taxis (21.2％), Self-Defense Force vehicles (12.7％), and helicopters
(9.4％) were used as conditions required. 
（50～100km 圏内では，救急車搬送のほうが早い場合もある）

![DMAT](http://www.regid.irides.tohoku.ac.jp/image/netlogo/dmat.jpg)

![SARCurve](http://www.regid.irides.tohoku.ac.jp/image/netlogo/SearchAndRescueCurve.jpg)

![IRIDeS](http://www.regid.irides.tohoku.ac.jp/image/irides_small.jpg)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

ambulance
false
0
Rectangle -7500403 true true 30 90 210 195
Polygon -7500403 true true 296 190 296 150 259 134 244 104 210 105 210 190
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Circle -16777216 true false 69 174 42
Rectangle -1 true false 288 158 297 173
Rectangle -1184463 true false 289 180 298 172
Rectangle -2674135 true false 29 151 298 158
Line -16777216 false 210 90 210 195
Rectangle -16777216 true false 83 116 128 133
Rectangle -16777216 true false 153 111 176 134
Line -7500403 true 165 105 165 135
Rectangle -7500403 true true 14 186 33 195
Line -13345367 false 45 135 75 120
Line -13345367 false 75 135 45 120
Line -13345367 false 60 112 60 142

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

building institution
false
0
Rectangle -7500403 true true 0 60 300 270
Rectangle -16777216 true false 130 196 168 256
Rectangle -16777216 false false 0 255 300 270
Polygon -7500403 true true 0 60 150 15 300 60
Polygon -16777216 false false 0 60 150 15 300 60
Circle -1 true false 135 26 30
Circle -16777216 false false 135 25 30
Rectangle -16777216 false false 0 60 300 75
Rectangle -16777216 false false 218 75 255 90
Rectangle -16777216 false false 218 240 255 255
Rectangle -16777216 false false 224 90 249 240
Rectangle -16777216 false false 45 75 82 90
Rectangle -16777216 false false 45 240 82 255
Rectangle -16777216 false false 51 90 76 240
Rectangle -16777216 false false 90 240 127 255
Rectangle -16777216 false false 90 75 127 90
Rectangle -16777216 false false 96 90 121 240
Rectangle -16777216 false false 179 90 204 240
Rectangle -16777216 false false 173 75 210 90
Rectangle -16777216 false false 173 240 210 255
Rectangle -16777216 false false 269 90 294 240
Rectangle -16777216 false false 263 75 300 90
Rectangle -16777216 false false 263 240 300 255
Rectangle -16777216 false false 0 240 37 255
Rectangle -16777216 false false 6 90 31 240
Rectangle -16777216 false false 0 75 37 90
Line -16777216 false 112 260 184 260
Line -16777216 false 105 265 196 265

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dmat
false
15
Polygon -10899396 true false 195 90 165 210 255 210 225 90
Polygon -13345367 true false 120 75 90 195 180 195 150 75
Circle -1 true true 41 41 67
Circle -1 true true 116 71 67
Circle -1 true true 176 26 67
Circle -1 true true 101 11 67
Polygon -2674135 true false 60 105 30 225 120 225 90 105
Polygon -11221820 true false 135 135 105 255 195 255 165 135

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fire department
false
0
Polygon -7500403 true true 150 55 180 60 210 75 240 45 210 45 195 30 165 15 135 15 105 30 90 45 60 45 90 75 120 60
Polygon -7500403 true true 55 150 60 120 75 90 45 60 45 90 30 105 15 135 15 165 30 195 45 210 45 240 75 210 60 180
Polygon -7500403 true true 245 150 240 120 225 90 255 60 255 90 270 105 285 135 285 165 270 195 255 210 255 240 225 210 240 180
Polygon -7500403 true true 150 245 180 240 210 225 240 255 210 255 195 270 165 285 135 285 105 270 90 255 60 255 90 225 120 240
Circle -7500403 true true 60 60 180
Circle -16777216 false false 75 75 150

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

helicopter
true
5
Circle -10899396 true true 30 106 90
Polygon -13345367 true false 119 135 224 150 119 165 119 135
Rectangle -7500403 true false 15 105 15 105
Rectangle -1 true false 17 100 141 106
Rectangle -1 true false 198 144 240 148
Rectangle -1 true false 216 122 221 168
Polygon -1 true false 28 80 118 130 122 125 32 75
Polygon -1 true false 71 116 70 150 40 150 43 137 49 128 54 122 61 117

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

house two story
false
0
Polygon -7500403 true true 2 180 227 180 152 150 32 150
Rectangle -7500403 true true 270 75 285 255
Rectangle -7500403 true true 75 135 270 255
Rectangle -16777216 true false 124 195 187 256
Rectangle -16777216 true false 210 195 255 240
Rectangle -16777216 true false 90 150 135 180
Rectangle -16777216 true false 210 150 255 180
Line -16777216 false 270 135 270 255
Rectangle -7500403 true true 15 180 75 255
Polygon -7500403 true true 60 135 285 135 240 90 105 90
Line -16777216 false 75 135 75 180
Rectangle -16777216 true false 30 195 93 240
Line -16777216 false 60 135 285 135
Line -16777216 false 255 105 285 135
Line -16777216 false 0 180 75 180
Line -7500403 true 60 195 60 240
Line -7500403 true 154 195 154 255

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person doctor
false
0
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Polygon -13345367 true false 135 90 150 105 135 135 150 150 165 135 150 105 165 90
Polygon -7500403 true true 105 90 60 195 90 210 135 105
Polygon -7500403 true true 195 90 240 195 210 210 165 105
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 79 172 94
Polygon -1 true false 105 90 60 195 90 210 114 156 120 195 90 270 210 270 180 195 186 155 210 210 240 195 195 90 165 90 150 150 135 90
Line -16777216 false 150 148 150 270
Line -16777216 false 196 90 151 149
Line -16777216 false 104 90 149 149
Circle -1 true false 180 0 30
Line -16777216 false 180 15 120 15
Line -16777216 false 150 195 165 195
Line -16777216 false 150 240 165 240
Line -16777216 false 150 150 165 150

person service
false
0
Polygon -7500403 true true 180 195 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285
Polygon -1 true false 120 90 105 90 60 195 90 210 120 150 120 195 180 195 180 150 210 210 240 195 195 90 180 90 165 105 150 165 135 105 120 90
Polygon -1 true false 123 90 149 141 177 90
Rectangle -7500403 true true 123 76 176 92
Circle -7500403 true true 110 5 80
Line -13345367 false 121 90 194 90
Line -16777216 false 148 143 150 196
Rectangle -16777216 true false 116 186 182 198
Circle -1 true false 152 143 9
Circle -1 true false 152 166 9
Rectangle -16777216 true false 179 164 183 186
Polygon -2674135 true false 180 90 195 90 183 160 180 195 150 195 150 135 180 90
Polygon -2674135 true false 120 90 105 90 114 161 120 195 150 195 150 135 120 90
Polygon -2674135 true false 155 91 128 77 128 101
Rectangle -16777216 true false 118 129 141 140
Polygon -2674135 true false 145 91 172 77 172 101

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.3.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>count victims with [color = gray]
count victims with [color = gray and hidden? = false]</final>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-ambulances">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-dmat">
      <value value="11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-helicopters">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#dmat">
      <value value="0"/>
      <value value="5"/>
      <value value="10"/>
      <value value="20"/>
      <value value="40"/>
      <value value="80"/>
      <value value="160"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_dmat0~200_ambulance100" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count victims with [color = gray]</metric>
    <metric>count victims with [color = gray and hidden? = false]</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-ambulances">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-dmat">
      <value value="11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-helicopters">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="#dmat" first="0" step="50" last="200"/>
  </experiment>
  <experiment name="experiment_dmat0~1000_ambulance100" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count victims with [color = gray]</metric>
    <metric>count victims with [color = gray and hidden? = false]</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-ambulances">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-dmat">
      <value value="11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#add-helicopters">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="#dmat" first="0" step="200" last="1000"/>
  </experiment>
  <experiment name="experiment_dmat0~1000_ambulance100" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count victims with [color = gray]</metric>
    <metric>count victims with [color = gray and hidden? = false]</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="#dmat" first="0" step="200" last="1000"/>
  </experiment>
  <experiment name="experiment_dmat0~10_ambulance100" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count victims with [color = gray]</metric>
    <metric>count victims with [color = gray and hidden? = false]</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="#dmat" first="0" step="1" last="10"/>
    <enumeratedValueSet variable="#ambulances">
      <value value="100"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_ambulance0~10_dmat10" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count victims with [color = gray]</metric>
    <metric>count victims with [color = gray and hidden? = false]</metric>
    <enumeratedValueSet variable="replicate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-heading">
      <value value="118"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="from-files?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="export-locations?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="label-distance">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="erase-previous-files?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="#dmat">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="#ambulances" first="0" step="1" last="10"/>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
