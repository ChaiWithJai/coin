import Foundation

enum TrainingCopy {
    static let table: [String: [String: String]] = [
        "tab_sessions": ["fr": "Séances", "en": "Sessions"],
        "tab_videos": ["fr": "Vidéos", "en": "Videos"],
        "tab_calendar": ["fr": "Calendrier", "en": "Calendar"],
        "home_headline": ["fr": "Allume la caméra. Entraîne-toi.", "en": "Camera on. Get to work."],
        "home_intro": ["fr": "Le coach mène l’échauffement, les rounds et le retour au calme.", "en": "Your coach leads the warm-up, rounds and cool-down."],
        "home_volume": ["fr": "VOLUME 01", "en": "VOLUME 01"],
        "home_eyebrow": ["fr": "TON FILM D'ENTRAÎNEMENT", "en": "YOUR TRAINING FILM"],
        "home_cinema_title": ["fr": "Entre dans le round.", "en": "Enter the round."],
        "home_cinema_subtitle": ["fr": "Pose ton téléphone. La caméra s'allume. Le coach mène la séance.", "en": "Set down your phone. The camera comes on. Your coach leads the session."],
        "home_tonight": ["fr": "LE DRILL DU JOUR", "en": "TODAY'S DRILL"],
        "home_drill_name": ["fr": "Ouvre. Combine. Sors.", "en": "Open. Combine. Exit."],
        "home_drill_flow": ["fr": "JAB  →  2–3 COUPS  →  ANGLE", "en": "JAB  →  2–3 PUNCHES  →  ANGLE"],
        "home_enter": ["fr": "ENTRER EN SÉANCE", "en": "ENTER THE SESSION"],
        "home_listen": ["fr": "ÉCOUTER LE COACH", "en": "HEAR THE COACH"],
        "home_opening_speech": ["fr": "Entre dans le round. Pose ton téléphone. Respire. On commence.", "en": "Enter the round. Set down your phone. Breathe. We begin."],
        "home_placement": ["fr": "Au sol, de côté, près du sac : fais avec l'angle que tu as. Le minuteur et la voix continuent même si le corps sort du cadre.", "en": "Floor, side angle, near the bag: use the view you have. Timer and voice continue even when your body leaves the frame."],
        "in_progress": ["fr": "En cours", "en": "In progress"],
        "resume_session": ["fr": "Reprendre la séance de %d min", "en": "Resume %d-min session"],
        "home_active_session": ["fr": "SÉANCE EN COURS", "en": "SESSION IN PROGRESS"],
        "choose_duration": ["fr": "Choisir une durée", "en": "Choose a duration"],
        "round_count": ["fr": "%d reprises", "en": "%d rounds"],
        "training_log": ["fr": "Journal", "en": "Training log"],
        "no_completed_sessions": ["fr": "Tes séances terminées apparaîtront ici.", "en": "Completed sessions appear here."],
        "session_log_line": ["fr": "%d reprises terminées · %d min au chrono", "en": "%d rounds elapsed · %d timer min"],
        "calendar_elapsed": ["fr": "%@ au chrono", "en": "%@ on the clock"],
        "recent_training_days": ["fr": "Jours d'entraînement", "en": "Training days"],
        "all_sessions_day": ["fr": "Voir les %d séances du jour", "en": "View all %d sessions today"],
        "drills": ["fr": "Drills", "en": "Drills"],
        "session_summary": ["fr": "%d reprises terminées · %d / %d min écoulées", "en": "%d rounds on timer · %d / %d min elapsed"],
        "recap_eyebrow": ["fr": "FIN DE SÉANCE", "en": "SESSION COMPLETE"],
        "recap_title": ["fr": "C'est dans la boîte.", "en": "That's a wrap."],
        "recap_early_title": ["fr": "Séance enregistrée.", "en": "Session saved."],
        "recap_clock_summary": ["fr": "%@ / %d min · %d reprises terminées", "en": "%@ / %d min · %d rounds finished"],
        "recap_rounds": ["fr": "Reprises terminées", "en": "Timed rounds"],
        "recap_camera": ["fr": "Échantillons caméra", "en": "Camera samples"],
        "recap_cues": ["fr": "Consignes demandées", "en": "Cues requested"],
        "recap_evidence": ["fr": "Le minuteur indique le temps écoulé. La caméra indique la visibilité du corps, pas la qualité de l'exercice.", "en": "The timer shows elapsed rounds. Camera samples show visibility only, not drill quality."],
        "recap_drills": ["fr": "REPRISES ENTAMÉES", "en": "ROUNDS REACHED"],
        "recap_round_elapsed": ["fr": "%@ au chrono · terminé", "en": "%@ timed · finished"],
        "recap_round_skipped": ["fr": "%@ au chrono · passé", "en": "%@ timed · skipped"],
        "recap_round_early": ["fr": "%@ au chrono · séance arrêtée", "en": "%@ timed · session ended"],
        "recap_reflection": ["fr": "UNE CHOSE À RETENIR", "en": "ONE THING TO KEEP"],
        "recap_placeholder": ["fr": "Une note pour ta prochaine reprise (facultatif)", "en": "A note for your next round (optional)"],
        "recap_save_note": ["fr": "Enregistrer la note", "en": "Save note"],
        "recap_view_log": ["fr": "Voir le journal de séance", "en": "View session log"],
        "session_evidence_note": ["fr": "Le minuteur et la caméra consignent ce qui a été observé. Ils ne confirment pas la qualité de l'exercice.", "en": "The timer and camera record what was observed. They do not verify drill quality."],
        "session_plan": ["fr": "Déroulé", "en": "Session plan"],
        "session_observed": ["fr": "Parcours de séance", "en": "Session record"],
        "session_remaining_plan": ["fr": "Étapes non commencées", "en": "Not started"],
        "session_no_observed": ["fr": "Aucune étape chronométrée.", "en": "No timed segment yet."],
        "segment_time_only": ["fr": "%d:%02d au chrono", "en": "%d:%02d timed"],
        "session_link_video": ["fr": "Associer une vidéo", "en": "Link a video"],
        "session_no_linked_video": ["fr": "Aucune vidéo associée.", "en": "No linked video."],
        "cue_request_one": ["fr": "1 consigne audio demandée", "en": "1 audio cue requested"],
        "round_drill": ["fr": "Reprise %d · %@", "en": "Round %d · %@"],
        "pose_samples": ["fr": "Cadrage complet sur %d / %d échantillons caméra", "en": "Full-body framing in %d / %d camera samples"],
        "pose_upload_receipts": ["fr": "%d / %d échantillons sélectionnés reçus par le serveur", "en": "%d / %d selected samples acknowledged by the server"],
        "pose_processing_p95": ["fr": "Traitement caméra → pose, p95 : %d ms", "en": "Camera callback → pose processing, p95: %d ms"],
        "cue_requests": ["fr": "%d consignes audio demandées", "en": "%d audio cues requested"],
        "segment_timing": ["fr": "%d:%02d au chrono · %d segments passés", "en": "%d:%02d timed · %d segments skipped"],
        "pose_sharing_on": ["fr": "Données de pose partagées", "en": "Pose data sharing on"],
        "pose_sharing_offline": ["fr": "Serveur de pose indisponible", "en": "Pose server unavailable"],
        "connection_private_server": ["fr": "Serveur privé", "en": "Private server"],
        "connection_access_key": ["fr": "Clé d’accès", "en": "Access key"],
        "connection_key_note": ["fr": "La clé reste dans le trousseau de cet iPhone. Les résumés de rounds et tes demandes d’analyse vont à ton serveur privé. Les images restent sur cet iPhone.", "en": "The key stays in this iPhone’s Keychain. Completed round summaries and requested reviews go to your private server. Images stay on this iPhone."],
        "connection_pose_tracking": ["fr": "Suivi de pose", "en": "Pose tracking"],
        "connection_pose_share": ["fr": "Partager les données de pose pendant la séance", "en": "Share pose data during workouts"],
        "connection_pose_note": ["fr": "Si activé, l'app envoie environ un échantillon toutes les dix secondes à ton serveur privé : nombre de points suivis, cadrage, visibilité du bas du corps, mouvement des poignets et délai de traitement. Aucune image ni vidéo n'est envoyée. La séance continue si le serveur est indisponible.", "en": "When enabled, the app sends about one sample every ten seconds to your private server: tracked point counts, framing, lower-body visibility, wrist movement and processing delay. No image or video is sent. Your workout continues if the server is offline."],
        "connection_https_error": ["fr": "Utilise une adresse HTTPS valide.", "en": "Use a valid HTTPS address."],
        "connection_key_error": ["fr": "La clé n’a pas pu être enregistrée.", "en": "Could not save the key."],
        "connection_title": ["fr": "Connexion", "en": "Connection"],
        "connection_close": ["fr": "Fermer", "en": "Close"],
        "guard_confirmed_note": ["fr": "Main arrière basse (repérée par l’analyse, confirmée)", "en": "Rear hand low (flagged by analysis, confirmed)"],
        "guard_advice_no_person": ["fr": "Tu sors souvent du cadre. Pose le téléphone sur un support fixe à 2–3 m, tout le haut du corps visible.", "en": "You are often out of frame. Put the phone on a fixed stand 2–3 m away with your whole upper body visible."],
        "guard_advice_too_close": ["fr": "Le téléphone est trop près. Recule-le à 2–3 m.", "en": "The phone is too close. Move it back to 2–3 m."],
        "guard_advice_joints_hidden": ["fr": "Épaules ou poignets cachés. Filme de face ou de trois-quarts, le sac sur le côté.", "en": "Shoulders or wrists are hidden. Film from the front or three-quarters, with the bag to the side."],
        "guard_advice_boxer_too_small": ["fr": "Tu es trop petit dans l’image. Rapproche le téléphone.", "en": "You are too small in the frame. Move the phone closer."],
        "guard_advice_multiple_people": ["fr": "Plusieurs personnes à l’image : l’analyse ne sait pas qui tu es. Filme-toi seul.", "en": "Several people are in frame, so the analysis cannot tell which one is you. Film yourself alone."],
        "guard_advice_default": ["fr": "Pas assez d’images exploitables.", "en": "Not enough usable footage."],
        "guard_title": ["fr": "Ma garde (bêta)", "en": "My guard (beta)"],
        "guard_instruction": ["fr": "Marque le début et la fin du round, puis lance l’analyse. Tout reste sur ton téléphone.", "en": "Mark where the round starts and ends, then analyse. Everything stays on your phone."],
        "guard_start": ["fr": "Début : %@", "en": "Start: %@"],
        "guard_end": ["fr": "Fin : %@", "en": "End: %@"],
        "guard_analyse": ["fr": "Analyser ma garde", "en": "Analyse my guard"],
        "guard_analysis_failed": ["fr": "L’analyse a échoué. Réessaie.", "en": "Analysis failed. Try again."],
        "guard_coverage": ["fr": "Analysable : %d %% du round", "en": "Analysable: %d%% of the round"],
        "guard_no_candidates": ["fr": "Aucune main arrière basse repérée dans les passages visibles.", "en": "No dropped rear hand found in the visible parts."],
        "guard_candidate": ["fr": "Main arrière basse ?", "en": "Rear hand low?"],
        "guard_confirmed": ["fr": "Confirmé", "en": "Confirmed"],
        "guard_rejected": ["fr": "Rejeté", "en": "Rejected"],
        "guard_yes": ["fr": "Oui", "en": "Yes"],
        "guard_no": ["fr": "Non", "en": "No"],
        "guard_limit": ["fr": "Repérage automatique à confirmer, pas un avis de coach.", "en": "Automatic flags for you to confirm, not coaching advice."],
        "film_headline": ["fr": "Une reprise. Un point à travailler.", "en": "One round. One thing to practise."],
        "film_intro": ["fr": "Ton carnet vidéo, au bord du ring.", "en": "Your video notebook at ringside."],
        "film_import": ["fr": "Importer une reprise", "en": "Import a round"],
        "film_record": ["fr": "Filmer une reprise", "en": "Record a round"],
        "film_my_rounds": ["fr": "Mes reprises", "en": "My rounds"],
        "film_empty_headline": ["fr": "Ta prochaine reprise commence ici", "en": "Your next round starts here"],
        "film_empty_detail": ["fr": "Ajoute une vidéo. Marque les moments à revoir.", "en": "Add a video. Mark the moments to review."],
        "film_in_development": ["fr": "En préparation", "en": "In development"],
        "film_live_feedback": ["fr": "Conseils en direct", "en": "Live feedback"],
        "film_live_note": ["fr": "Les conseils vidéo en direct sont en développement. Les plans utilisent tes notes.", "en": "Live video feedback is in development. Plans use your notes."],
        "film_stance": ["fr": "Garde", "en": "Stance"],
        "film_orthodox": ["fr": "Orthodoxe", "en": "Orthodox"],
        "film_southpaw": ["fr": "Gaucher", "en": "Southpaw"],
        "film_importing": ["fr": "Importation…", "en": "Importing…"],
        "film_settings": ["fr": "Réglages", "en": "Settings"],
        "film_done": ["fr": "Terminé", "en": "Done"],
        "film_edit": ["fr": "Modifier", "en": "Edit"],
        "film_error_title": ["fr": "Impossible de terminer", "en": "Unable to finish"],
        "film_error_detail": ["fr": "Impossible d’enregistrer ou d’ouvrir cette vidéo. Vérifie le fichier et l’espace disponible.", "en": "Could not save or open this video. Check the file and available storage."],
        "film_note_placeholder": ["fr": "Ce que tu observes…", "en": "What do you notice…"],
        "film_mark_moment": ["fr": "Noter ce moment", "en": "Mark this moment"],
        "film_notes_help": ["fr": "Tes observations · touche une note pour revoir le moment", "en": "Your observations · tap a note to replay the moment"],
        "film_next_focus": ["fr": "À travailler", "en": "Your next focus"],
        "film_legacy_plan": ["fr": "Ce plan ancien doit être régénéré dans la langue choisie.", "en": "Generate this older plan again in your selected language."],
        "film_plan_next": ["fr": "Préparer le prochain round", "en": "Plan the next round"],
        "film_send_note": ["fr": "Envoie tes notes au serveur privé. La vidéo reste sur ton téléphone.", "en": "Sends your notes to the private server. Video stays on your phone."],
        "film_round_title": ["fr": "Séance", "en": "Round"],
        "film_limitation": ["fr": "Suggestion fondée uniquement sur les observations que tu as notées ou confirmées. À valider avec ton coach.", "en": "Suggestion based only on observations you noted or confirmed. Check it with your coach."],
        "session_videos": ["fr": "Vidéos de cette séance", "en": "Session videos"],
        "no_videos": ["fr": "Importe ou filme un round dans Vidéos, puis relie-le ici.", "en": "Import or record a round in Videos, then link it here."],
        "reflection": ["fr": "Bilan", "en": "Reflection"],
        "review_evidence_note": ["fr": "Les durées proviennent du minuteur. Les échantillons MediaPipe montrent seulement si le corps était visible. Les vidéos liées se consultent séparément.", "en": "Durations come from the timer. MediaPipe samples only show whether a body was visible. Linked videos can be reviewed separately."],
        "finish_save_log": ["fr": "Terminer et enregistrer", "en": "Finish and save log"],
        "no_reflection": ["fr": "Aucune note ajoutée.", "en": "No reflection added."],
        "session_title": ["fr": "Séance", "en": "Session"],
        "finish": ["fr": "Terminer", "en": "Finish"],
        "worked_on": ["fr": "Ce que tu as travaillé", "en": "What you worked on"],
        "reflection_placeholder": ["fr": "Une note pour ton journal", "en": "A note for your log"],
        "finish_note": ["fr": "Tu peux terminer avec des rounds non terminés. Le journal gardera le plan et les durées écoulées.", "en": "You can finish with rounds left open. The log keeps the plan and elapsed time."],
        "finish_session": ["fr": "Fin de séance", "en": "Finish session"],
        "cancel": ["fr": "Annuler", "en": "Cancel"],
        "save": ["fr": "Enregistrer", "en": "Save"],
        "training_days": ["fr": "Jours d’entraînement", "en": "Training days"],
        "calendar_planning": ["fr": "Plan du camp", "en": "Camp plan"],
        "day": ["fr": "Jour", "en": "Day"],
        "no_session_day": ["fr": "Aucune séance ce jour-là.", "en": "No session on this day."],
        "calendar_session_line": ["fr": "%d reprises · %@", "en": "%d rounds · %@"],
        "completed": ["fr": "terminée", "en": "finished"],
        "ongoing": ["fr": "en cours", "en": "in progress"],
        "interrupted": ["fr": "interrompue", "en": "interrupted"],
        "interrupted_note": ["fr": "Séance interrompue lorsqu’une nouvelle séance a commencé.", "en": "Session stopped when a new workout began."],
        "camp_dates": ["fr": "Dates du camp", "en": "Camp dates"],
        "weight_log": ["fr": "Poids noté", "en": "Weight log"],
        "latest_weight": ["fr": "Dernière note : %@ %@ · %@", "en": "Latest entry: %@ %@ · %@"],
        "measured_weight": ["fr": "Poids mesuré", "en": "Measured weight"],
        "unit": ["fr": "Unité", "en": "Unit"],
        "log_weight": ["fr": "Noter le poids", "en": "Log weight"],
        "weight_note": ["fr": "Journal de mesures uniquement. Les changements de poids se préparent avec ton équipe.", "en": "Measurement log only. Plan weight changes with your team."],
        "add_camp_date": ["fr": "Ajouter un repère", "en": "Add a camp date"],
        "type": ["fr": "Type", "en": "Type"],
        "date": ["fr": "Date", "en": "Date"],
        "camp_date_name": ["fr": "Nom du repère", "en": "Name this date"],
        "weight_class_optional": ["fr": "Catégorie de poids (facultatif)", "en": "Weight class (optional)"],
        "save_date": ["fr": "Enregistrer la date", "en": "Save date"],
        "pre_sparring_note": ["fr": "Le point avant sparring est un repère pour en parler avec ton coach. L’app ne donne pas d’autorisation médicale.", "en": "The pre-sparring check is a date to discuss with your coach. The app does not give medical clearance."],
        "milestone_weigh_in": ["fr": "Pesée", "en": "Weigh-in"],
        "milestone_readiness_check": ["fr": "Point avant sparring", "en": "Pre-sparring check"],
        "milestone_fight_date": ["fr": "Combat", "en": "Fight"],
        "milestone_weight_class": ["fr": "Campagne de catégorie", "en": "Weight-class campaign"],
        "camera_privacy": ["fr": "L’image reste sur l’appareil. Aucun round n’est sauvegardé automatiquement.", "en": "Video stays on device. Rounds are not saved automatically."],
        "warmup_title": ["fr": "ÉCHAUFFEMENT", "en": "WARM-UP"],
        "rest_title": ["fr": "RÉCUPÉRATION", "en": "REST"],
        "cooldown_title": ["fr": "RETOUR AU CALME", "en": "COOL-DOWN"],
        "round_title": ["fr": "REPRISE %d", "en": "ROUND %d"],
        "phase_jab": ["fr": "1 · JAB", "en": "1 · JAB"],
        "phase_combine": ["fr": "2 · COMBINE", "en": "2 · COMBINATION"],
        "phase_angle": ["fr": "3 · ANGLE", "en": "3 · ANGLE"],
        "phase_guard": ["fr": "2 · GARDE", "en": "2 · GUARD"],
        "cycle_unverified": ["fr": "Cycle à travailler · détection en cours de validation", "en": "Practice cycle · detection under validation"],
        "current_focus": ["fr": "À faire maintenant", "en": "Focus now"],
        "rest_instruction": ["fr": "Respire. Le prochain round arrive.", "en": "Breathe. Next round is coming."],
        "start": ["fr": "Commencer", "en": "Start"],
        "pause": ["fr": "Pause", "en": "Pause"],
        "mute": ["fr": "Couper la voix", "en": "Mute voice"],
        "unmute": ["fr": "Activer la voix", "en": "Unmute voice"],
        "switch_camera": ["fr": "Changer de caméra", "en": "Switch camera"],
        "skip": ["fr": "Passer au suivant", "en": "Skip to next"],
        "workout_complete": ["fr": "Séance terminée", "en": "Workout complete"],
        "finish_workout_question": ["fr": "Terminer la séance ?", "en": "Finish workout?"],
        "finish_now": ["fr": "Terminer maintenant", "en": "Finish now"],
        "cooldown_speech": ["fr": "Retour au calme. Ralentis et respire.", "en": "Cool down. Slow down and breathe."],
        "rest_speech": ["fr": "Récupération. Respire.", "en": "Rest. Breathe."],
        "round_speech": ["fr": "Jab, combinaison, sortie en angle.", "en": "Jab, combination, angle exit."],
        "guard_round_speech": ["fr": "Après chaque coup, reviens en garde.", "en": "Return to guard after every punch."],
        "footwork_round_speech": ["fr": "Déplace-toi, tourne, puis réinitialise ta position.", "en": "Step, turn, then reset your position."],
        "free_round_speech": ["fr": "Round libre. Reste attentif à ta garde et à tes appuis.", "en": "Open round. Stay aware of your guard and footwork."],
        "probe_mid_cue": ["fr": "Jab pour ouvrir. Deux ou trois coups, puis sors en angle.", "en": "Probe with the jab. Two or three punches, then exit on an angle."],
        "probe_late_cue": ["fr": "Reviens en garde, change d'angle, puis recommence.", "en": "Recover your guard, change angle, then repeat."],
        "guard_mid_cue": ["fr": "Après le jab, ramène la main tout de suite.", "en": "After the jab, bring your hand straight back."],
        "guard_late_cue": ["fr": "Garde les mains en place entre les coups.", "en": "Keep your hands in position between punches."],
        "footwork_mid_cue": ["fr": "Fais un pas, tourne, retrouve tes appuis.", "en": "Step, turn, find your stance again."],
        "footwork_late_cue": ["fr": "Sors de la ligne avant de recommencer.", "en": "Move off the line before you start again."],
        "free_mid_cue": ["fr": "Une minute écoulée. Continue à ton rythme.", "en": "One minute down. Keep your rhythm."],
        "free_late_cue": ["fr": "Dernière minute. Reste propre dans tes mouvements.", "en": "Final minute. Keep your movements clean."],
        "speech_locale": ["fr": "fr-FR", "en": "en-US"],
    ]
    static let base: [String: [String: String]] = [
            "warmup": ["fr": "Échauffement", "en": "Warm-up"],
            "cooldown": ["fr": "Retour au calme", "en": "Cool-down"],
            "probe_combine_angle": ["fr": "Jab · combinaison · sortie en angle", "en": "Jab · combination · angle exit"],
            "guard_return": ["fr": "Retour en garde", "en": "Return to guard"],
            "footwork": ["fr": "Déplacements et angles", "en": "Footwork and angles"],
            "free_boxing": ["fr": "Boxe libre", "en": "Open round"],
            "boxing": ["fr": "Boxe", "en": "Boxing"],
            "rest": ["fr": "Récupération", "en": "Rest"],
            "pose_waiting": ["fr": "Recherche du corps", "en": "Waiting for body"],
            "pose_model_unavailable": ["fr": "Modèle de pose indisponible", "en": "Pose model unavailable"],
            "pose_error": ["fr": "Erreur de suivi", "en": "Tracking error"],
            "pose_absent": ["fr": "Suivi limité · séance en cours", "en": "Limited view · workout continues"],
            "pose_visible": ["fr": "Corps visible", "en": "Body visible"],
            "pose_partial": ["fr": "Vue partielle · séance en cours", "en": "Partial view · workout continues"],
            "pose_legs_visible": ["fr": "Jambes visibles · répétitions suivies", "en": "Legs visible · tracking reps"],
            "pose_show_legs": ["fr": "Montre hanches, genoux et chevilles", "en": "Show hips, knees and ankles"],
            "camera_starting": ["fr": "Démarrage caméra", "en": "Starting camera"],
            "camera_unavailable": ["fr": "Caméra indisponible", "en": "Camera unavailable"],
            "camera_permission": ["fr": "Autorise la caméra", "en": "Allow camera access"],
            "camera_on": ["fr": "Caméra active", "en": "Camera on"],
            "framing_cue": ["fr": "Replace-toi dans le cadre pour que je puisse te suivre.", "en": "Move back into frame so I can track you."],
            "mobility": ["fr": "Mobilité", "en": "Mobility"],
            "squats": ["fr": "Squats", "en": "Squats"],
            "squat_observed_reps": ["fr": "%d squats observés", "en": "%d squats observed"],
            "lunge_observed_reps": ["fr": "%d fentes observées", "en": "%d lunges observed"],
            "lunges": ["fr": "Fentes", "en": "Lunges"],
            "shadowboxing": ["fr": "Boxe dans le vide", "en": "Shadowboxing"],
            "pushups": ["fr": "Pompes", "en": "Push-ups"],
            "bench_press": ["fr": "Développé couché", "en": "Bench press"],
            "mobility_cue": ["fr": "Mobilité. Bouge les épaules, les hanches et les chevilles.", "en": "Mobility. Move your shoulders, hips and ankles."],
            "squats_cue": ["fr": "Squats. Descends avec contrôle, puis remonte.", "en": "Squats. Lower with control, then stand."],
            "lunges_cue": ["fr": "Fentes. Alterne les jambes et garde ton équilibre.", "en": "Lunges. Alternate legs and keep your balance."],
            "shadowboxing_cue": ["fr": "Boxe dans le vide. Jab léger, garde haute, petits pas.", "en": "Shadowbox. Light jab, hands up, small steps."],
    ]
    static func text(_ key: String, _ language: String) -> String {
        return (table[key] ?? base[key])?[language] ?? (table[key] ?? base[key])?["en"] ?? key
    }
    static func format(_ key: String, _ language: String, _ values: CVarArg...) -> String {
        String(format: text(key, language), arguments: values)
    }
}

struct BoxingDrill: Codable, Identifiable, Hashable {
    let id: String
    let goalKey: String
    let phases: [String]
    let cueIDs: [String]
}

enum DrillLibrary {
    static let all: [BoxingDrill] = [
        .init(id: "probe-combine-angle-v1", goalKey: "probe_combine_angle", phases: ["initiate", "interact", "terminate", "angle", "reset"], cueIDs: ["probe_first", "finish_combination", "recover_guard", "exit_and_angle"]),
        .init(id: "guard-return-v1", goalKey: "guard_return", phases: ["jab", "recover_guard", "reset"], cueIDs: ["recover_guard"]),
        .init(id: "footwork-angle-v1", goalKey: "footwork", phases: ["step", "turn", "reset"], cueIDs: ["exit_and_angle"]),
        .init(id: "free-boxing-v1", goalKey: "free_boxing", phases: [], cueIDs: []),
    ]
    static func name(_ id: String, language: String) -> String {
        guard let drill = all.first(where: { $0.id == id }) else { return id }
        return TrainingCopy.text(drill.goalKey, language)
    }
    static func speechKey(_ id: String) -> String {
        switch id {
        case "guard-return-v1": return "guard_round_speech"
        case "footwork-angle-v1": return "footwork_round_speech"
        case "free-boxing-v1": return "free_round_speech"
        default: return "round_speech"
        }
    }
    static func phaseKeys(_ id: String) -> [String] {
        switch id {
        case "probe-combine-angle-v1": return ["phase_jab", "phase_combine", "phase_angle"]
        case "guard-return-v1": return ["phase_jab", "phase_guard"]
        default: return []
        }
    }
    static func pacingCueKey(_ id: String, remainingSeconds: Int) -> String? {
        let suffix: String
        switch remainingSeconds {
        case 120: suffix = "mid_cue"
        case 60: suffix = "late_cue"
        default: return nil
        }
        let prefix: String
        switch id {
        case "probe-combine-angle-v1": prefix = "probe"
        case "guard-return-v1": prefix = "guard"
        case "footwork-angle-v1": prefix = "footwork"
        case "free-boxing-v1": prefix = "free"
        default: return nil
        }
        return "\(prefix)_\(suffix)"
    }
    static func focusCueKey(_ id: String, remainingSeconds: Int) -> String {
        if remainingSeconds <= 60 { return pacingCueKey(id, remainingSeconds: 60) ?? speechKey(id) }
        if remainingSeconds <= 120 { return pacingCueKey(id, remainingSeconds: 120) ?? speechKey(id) }
        return speechKey(id)
    }
}

enum SessionBlockKind: String, Codable { case warmup, boxing, cooldown, exercise, recovery }
enum BlockCompletionMode: String, Codable { case timed, manual }

enum ActivitySelectionProvenance: String, Codable {
    case sourceSpecified = "source_specified", userSelected = "user_selected", unchosen
}
enum ActivityMeasurementCapability: String, Codable {
    case repCandidate = "rep_candidate", exchangeCandidate = "exchange_candidate"
    case elapsedOnly = "elapsed_only", unsupported
}
enum ActivityMeasurementValidation: String, Codable {
    case unvalidated, notApplicable = "not_applicable"
}

enum ActivityIntervalExitReason: String, Codable {
    case choiceChanged = "choice_changed", segmentEnded = "segment_ended"
    case sessionFinished = "session_finished", paused
}

/// Timer attribution to a chosen runtime object, not proof that its movement was performed.
struct WorkoutActivityInterval: Codable, Identifiable, Equatable {
    var id = UUID()
    let blockID: UUID
    let preparationIndex: Int?
    let activityInstanceID: UUID
    let startElapsedSeconds: Int
    let endElapsedSeconds: Int
    let exitReason: ActivityIntervalExitReason
    let closedAt: Date
    let baselineOnly: Bool
    var elapsedSeconds: Int { endElapsedSeconds - startElapsedSeconds }
    var payload: [String: Any] {
        var result: [String: Any] = ["interval_id": id.uuidString, "block_id": blockID.uuidString,
            "activity_instance_id": activityInstanceID.uuidString, "start_elapsed_seconds": startElapsedSeconds,
            "end_elapsed_seconds": endElapsedSeconds, "elapsed_seconds": elapsedSeconds,
            "exit_reason": exitReason.rawValue, "closed_at_ms": Int(closedAt.timeIntervalSince1970 * 1000),
            "baseline_only": baselineOnly, "evidence": "workout_timer_not_verified_activity"]
        result["preparation_index"] = preparationIndex
        return result
    }
}
enum WorkoutActivityCopy {
    static func name(_ key: String?, customName: String? = nil, language: String) -> String {
        if let customName, !customName.isEmpty { return customName }
        let names: [String: [String: String]] = [
            "jumping_jacks": ["fr": "Jumping jacks", "en": "Jumping jacks"],
            "burpees": ["fr": "Burpees", "en": "Burpees"],
            "box_jumps": ["fr": "Sauts sur caisse", "en": "Box jumps"],
            "frontal_stance": ["fr": "Garde de face", "en": "Frontal stance"],
            "squat_jumps": ["fr": "Squats sautés", "en": "Squat jumps"],
            "squats": ["fr": "Squats", "en": "Squats"],
            "lunges": ["fr": "Fentes", "en": "Lunges"],
            "mobility": ["fr": "Mobilité", "en": "Mobility"],
            "shadowboxing": ["fr": "Boxe dans le vide", "en": "Shadowboxing"],
            "boxing": ["fr": "Boxe", "en": "Boxing"],
            "custom": ["fr": "Libre", "en": "Custom"]
        ]
        guard let key else { return language == "fr" ? "Non choisi" : "Unchosen" }
        return names[key]?[language] ?? key.replacingOccurrences(of: "_", with: " ")
    }
}
struct ActivityMeasurementRecipe: Codable, Equatable {
    let id: String
    let version: String
    let capability: ActivityMeasurementCapability
    let validationStatus: ActivityMeasurementValidation

    /// Versioned observation contract. These joints are inputs to a candidate,
    /// not proof that an exercise was performed or a rep was correct.
    var landmarkGroups: [[String]] {
        switch id {
        case "mediapipe-squat-angle", "mediapipe-lunge-angle":
            return [["left_hip", "left_knee", "left_ankle"],
                    ["right_hip", "right_knee", "right_ankle"]]
        case "coin-exchange-tracker":
            return [["left_shoulder", "right_shoulder", "left_wrist", "right_wrist", "left_hip", "right_hip"]]
        default: return []
        }
    }

    var visibilityRule: String { landmarkGroups.isEmpty ? "not_applicable" : "any_complete_group" }

    var observationUnit: String {
        switch capability {
        case .repCandidate: return "rep_candidate"
        case .exchangeCandidate: return "exchange_candidate"
        case .elapsedOnly: return "elapsed_seconds"
        case .unsupported: return "none"
        }
    }

    /// Only exact, implemented movements get candidate recognition. A clock measures no movement.
    static func forExercise(_ exerciseKey: String?) -> Self {
        switch exerciseKey {
        case "squats":
            return .init(id: "mediapipe-squat-angle", version: "v1", capability: .repCandidate, validationStatus: .unvalidated)
        case "lunges":
            return .init(id: "mediapipe-lunge-angle", version: "v1", capability: .repCandidate, validationStatus: .unvalidated)
        case "boxing", "shadowboxing":
            return .init(id: "coin-exchange-tracker", version: "v1", capability: .exchangeCandidate, validationStatus: .unvalidated)
        case nil, "unknown":
            return .init(id: "none", version: "v1", capability: .unsupported, validationStatus: .notApplicable)
        case "jumping_jacks", "burpees", "box_jumps", "squat_jumps", "frontal_stance", "mobility", "conditioning":
            return .init(id: "session-clock", version: "v1", capability: .elapsedOnly, validationStatus: .notApplicable)
        default:
            return .init(id: "session-clock", version: "v1", capability: .elapsedOnly, validationStatus: .notApplicable)
        }
    }
}

/// Runtime choices are separate from immutable source prescriptions. Re-selection appends history.
struct WorkoutActivityInstance: Codable, Identifiable, Equatable {
    var id = UUID()
    let blockID: UUID
    let preparationIndex: Int?
    let sourceBlockID: String?
    let sourceItemID: String?
    let exerciseKey: String?
    var customName: String? = nil
    let selectionProvenance: ActivitySelectionProvenance
    let measurement: ActivityMeasurementRecipe
    let selectedAt: Date?

    var payload: [String: Any] {
        var value: [String: Any] = ["instance_id": id.uuidString, "block_id": blockID.uuidString,
            "selection_provenance": selectionProvenance.rawValue,
            "measurement": ["id": measurement.id, "version": measurement.version,
                "capability": measurement.capability.rawValue, "validation_status": measurement.validationStatus.rawValue,
                "landmark_groups": measurement.landmarkGroups, "visibility_rule": measurement.visibilityRule,
                "observation_unit": measurement.observationUnit]]
        value["preparation_index"] = preparationIndex
        value["source_block_id"] = sourceBlockID
        value["source_item_id"] = sourceItemID
        value["exercise_key"] = exerciseKey
        if let selectedAt { value["selected_at_ms"] = Int(selectedAt.timeIntervalSince1970 * 1000) }
        return value
    }

    static func initial(for block: SessionBlock, at date: Date) -> [Self] {
        func make(_ key: String?, index: Int?) -> Self {
            let concrete = key == "unknown" ? nil : key
            return .init(blockID: block.id, preparationIndex: index, sourceBlockID: block.sourceBlockID,
                sourceItemID: block.sourceItemID, exerciseKey: concrete,
                selectionProvenance: concrete == nil ? .unchosen : .sourceSpecified,
                measurement: .forExercise(concrete), selectedAt: concrete == nil ? nil : date)
        }
        if let activities = block.activities, !activities.isEmpty {
            return activities.enumerated().map { make($0.element.key, index: $0.offset) }
        }
        let initialKey = block.activityChoiceFamily == nil
            ? (block.sourceActivityKey ?? (block.kind == .boxing ? "boxing" : nil)) : nil
        return [make(initialKey, index: nil)]
    }
}

enum WorkoutActivityRouting {
    static func allowsExchange(_ instance: WorkoutActivityInstance?) -> Bool {
        instance?.measurement.capability == .exchangeCandidate
    }
    static func changed(from previous: WorkoutActivityInstance?, to current: WorkoutActivityInstance?) -> Bool {
        previous?.id != current?.id
    }
    static func outgoingExchangeID(from previous: WorkoutActivityInstance?,
                                   to current: WorkoutActivityInstance?) -> UUID? {
        guard changed(from: previous, to: current), allowsExchange(previous) else { return nil }
        return previous?.id
    }
}

struct PreparationActivity: Codable, Hashable {
    let key: String
    let minutes: Int
}

enum PreparationCatalog {
    static let availableKeys = ["mobility", "squats", "lunges", "shadowboxing", "pushups", "bench_press"]
    static func defaultWarmup(minutes: Int) -> [PreparationActivity] {
        let each = minutes / 4
        return [
            .init(key: "mobility", minutes: each),
            .init(key: "squats", minutes: each),
            .init(key: "lunges", minutes: each),
            .init(key: "shadowboxing", minutes: minutes - each * 3),
        ]
    }
}

struct SessionBlock: Codable, Identifiable, Hashable {
    var id = UUID()
    let kind: SessionBlockKind
    let minutes: Int
    let roundNumber: Int?
    var drillID: String?
    let restAfterMinutes: Int
    var activities: [PreparationActivity]? = nil
    // Optional fields keep existing saved sessions readable. Source text remains
    // evidence for the workout prescription, separate from observed performance.
    var durationSeconds: Int? = nil
    var restAfterSeconds: Int? = nil
    var sourceTitle: String? = nil
    var sourceInstructions: String? = nil
    var sourceURL: String? = nil
    var sourceDemoURLs: [String]? = nil
    var sourceActivityKey: String? = nil
    var sourceBlockID: String? = nil
    var sourceItemID: String? = nil
    var repetitionText: String? = nil
    var completionMode: BlockCompletionMode? = nil
    // Runtime-choice metadata; never substitutes an exercise into the original source prescription.
    var activityChoiceFamily: String? = nil
    var effectiveSeconds: Int { max(0, durationSeconds ?? minutes * 60) }
    var effectiveRestSeconds: Int { max(0, restAfterSeconds ?? restAfterMinutes * 60) }
    var isManual: Bool { completionMode == .manual }
}

struct TrainingTemplate: Codable, Identifiable, Hashable {
    let id: String
    let durationMinutes: Int
    let blocks: [SessionBlock]
    var sourceTitle: String? = nil
    var sourceURL: String? = nil
    var sourceVersion: String? = nil
    var plannedSeconds: Int { blocks.reduce(0) { $0 + $1.effectiveSeconds + $1.effectiveRestSeconds } }
    var plannedMinutes: Int { Int(ceil(Double(plannedSeconds) / 60)) }
    var boxingRounds: Int { blocks.filter { $0.kind == .boxing }.count }
}

enum SessionTemplates {
    static let durations = [30, 50, 60, 75, 90]
    static func make(_ duration: Int) -> TrainingTemplate? {
        guard durations.contains(duration) else { return nil }
        let warmup = duration <= 30 ? 8 : (duration <= 60 ? 10 : (duration == 75 ? 12 : 15))
        let cooldown = duration <= 50 ? 5 : (duration <= 75 ? 6 : 8)
        let available = duration - warmup - cooldown
        let rounds = available / 4
        let transition = available - rounds * 4
        var warmupBlock = SessionBlock(kind: .warmup, minutes: warmup + transition, roundNumber: nil, drillID: nil, restAfterMinutes: 0)
        warmupBlock.activities = PreparationCatalog.defaultWarmup(minutes: warmup + transition)
        var blocks = [warmupBlock]
        for number in 1...rounds {
            blocks.append(SessionBlock(kind: .boxing, minutes: 3, roundNumber: number,
                                       drillID: "probe-combine-angle-v1", restAfterMinutes: 1))
        }
        blocks.append(SessionBlock(kind: .cooldown, minutes: cooldown, roundNumber: nil, drillID: nil, restAfterMinutes: 0))
        return TrainingTemplate(id: "standard-\(duration)-v1", durationMinutes: duration, blocks: blocks)
    }
    static var all: [TrainingTemplate] { durations.compactMap(make) }
    static func freestyle(rounds: Int = 6, roundSeconds: Int = 180, restSeconds: Int = 60) -> TrainingTemplate? {
        guard (1...30).contains(rounds), (10...3600).contains(roundSeconds),
              (0...600).contains(restSeconds) else { return nil }
        let blocks = (1...rounds).map { number in
            SessionBlock(kind: .boxing, minutes: roundSeconds / 60, roundNumber: number,
                         drillID: "free-boxing-v1", restAfterMinutes: number == rounds ? 0 : restSeconds / 60,
                         durationSeconds: roundSeconds, restAfterSeconds: number == rounds ? 0 : restSeconds,
                         completionMode: .timed)
        }
        let seconds = rounds * roundSeconds + (rounds - 1) * restSeconds
        return TrainingTemplate(id: "freestyle-\(rounds)-\(roundSeconds)-\(restSeconds)-v1",
                                durationMinutes: Int(ceil(Double(seconds) / 60)), blocks: blocks)
    }
}

enum SessionState: String, Codable { case planned, active, completed, interrupted }

struct BlockLog: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let recordedAt: Date
    let evidenceSource: String
}

struct SegmentLog: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let activityKey: String?
    let isRest: Bool
    let plannedSeconds: Int
    let elapsedSeconds: Int
    let exitReason: String
    let endedAt: Date
}

struct PoseSampleRecord: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let sampledAt: Date
    let landmarkCount: Int
    let sourceVersion: String
    var visibleLandmarkCount: Int? = nil
    var framingReady: Bool? = nil
    var captureToPoseMs: Double? = nil
    var wristTravelBodyWidths: Double? = nil
    var lowerBodyVisible: Bool? = nil
    var cameraFacing: String? = nil
    var remoteEventID: String? = nil
    var uploadLanguage: String? = nil
    var bodyVisible: Bool { framingReady == true }
}

struct ExerciseRepRecord: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let activityKey: String
    let observedAt: Date
    let sourceVersion: String
    var activityInstanceID: UUID? = nil
}

enum EngagementPhase: String, Codable { case initiate, interact, terminate, reset, unknown }
enum EngagementEvidenceSource: String, Codable { case poseCandidate, boxerReport, reviewedClip }

struct EngagementPhaseSpan: Codable, Identifiable {
    var id = UUID()
    let phase: EngagementPhase
    let startMs: Int
    let endMs: Int
    let source: EngagementEvidenceSource
    let classifierVersion: String?
}

struct EngagementAttempt: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let protocolID: String
    let startMs: Int
    let endMs: Int
    let spans: [EngagementPhaseSpan]
    let cameraCoverage: String
    let evidenceSource: EngagementEvidenceSource
    var boxerCorrection: String? = nil
    var acceptedAt: Date? = nil
    var isAccepted: Bool { acceptedAt != nil }
}

struct CoachCueRecord: Codable, Identifiable {
    var id = UUID()
    let blockID: UUID
    let requestedAt: Date
    let cueKey: String
    let language: String
    let trigger: String
}

enum WorkoutRuntimeOrigin: String, Codable {
    case physicalDevice = "physical_device", simulator, synthetic, replay, unknown
    static var current: Self {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COIN_TEST_ROUND_REVIEW"] == "1" { return .synthetic }
        #endif
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return .physicalDevice
        #endif
    }
}

/// A session-end receipt is evidence of app activity, never verified exercise adherence.
struct WorkoutCompletionReceipt: Codable, Identifiable {
    struct Block: Codable {
        let blockID: UUID
        let sourceBlockID: String?
        let sourceItemID: String?
        let completionSources: [String]
        let segments: [SegmentLog]
        let cueRequests: [CoachCueRecord]
    }
    var id = UUID()
    let sessionID: UUID
    let runtimeOrigin: WorkoutRuntimeOrigin
    let startedAt: Date?
    let endedAt: Date
    let sourceVersion: String?
    let blocks: [Block]
    var activityInstances: [WorkoutActivityInstance]? = nil
    var activityIntervals: [WorkoutActivityInterval]? = nil
    var remoteEventID: String? = nil

    func payload() -> [String: Any] {
        var result: [String: Any] = [
            "schema_version": "workout-completion-v1", "request_id": id.uuidString,
            "session_id": sessionID.uuidString, "runtime_origin": runtimeOrigin.rawValue,
            "ended_at_ms": Int(endedAt.timeIntervalSince1970 * 1000),
            "completion_evidence": "session_ended_not_verified_adherence", "pose_sharing_enabled": false,
            "blocks": blocks.map { block -> [String: Any] in
                var value: [String: Any] = ["block_id": block.blockID.uuidString,
                    "completion_sources": block.completionSources,
                    "segments": block.segments.map { ["segment_id": $0.id.uuidString,
                        "elapsed_seconds": $0.elapsedSeconds, "planned_seconds": $0.plannedSeconds,
                        "is_rest": $0.isRest, "exit_reason": $0.exitReason] as [String: Any] },
                    "cue_requests": block.cueRequests.map { ["cue_request_id": $0.id.uuidString,
                        "cue_key": $0.cueKey, "language": $0.language, "trigger": $0.trigger,
                        "requested_at_ms": Int($0.requestedAt.timeIntervalSince1970 * 1000),
                        "evidence": "requested_not_confirmed_playback"] as [String: Any] }]
                value["source_block_id"] = block.sourceBlockID
                value["source_item_id"] = block.sourceItemID
                return value
            }]
        result["source_version"] = sourceVersion
        if let activityInstances { result["activity_instances"] = activityInstances.map(\.payload) }
        if let activityIntervals { result["activity_intervals"] = activityIntervals.map(\.payload) }
        if let startedAt { result["started_at_ms"] = Int(startedAt.timeIntervalSince1970 * 1000) }
        return result
    }
}

struct TrainingSession: Codable, Identifiable {
    var id = UUID()
    let templateID: String
    let plannedMinutes: Int
    let createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var endReason: String? = nil
    var state: SessionState
    var blocks: [SessionBlock]
    var completedBlockIDs: [UUID] = []
    var blockLogs: [BlockLog]? = []
    var segmentLogs: [SegmentLog]? = []
    var poseWindows: [PoseSampleRecord]? = []
    var exerciseReps: [ExerciseRepRecord]? = []
    var engagementAttempts: [EngagementAttempt]? = []
    var cueRequests: [CoachCueRecord]? = []
    var linkedRoundIDs: [UUID] = []
    var reflection: String = ""
    var runtimeSegmentIndex: Int? = nil
    var runtimeRemainingSeconds: Int? = nil
    var runtimeElapsedSeconds: Int? = nil
    var timerElapsedSeconds: Int? = nil
    var sourceTitle: String? = nil
    var sourceURL: String? = nil
    var sourceVersion: String? = nil
    var runtimeOrigin: WorkoutRuntimeOrigin? = nil
    var completionReceipt: WorkoutCompletionReceipt? = nil
    var activityInstances: [WorkoutActivityInstance]? = nil
    var activityIntervals: [WorkoutActivityInterval]? = nil
    func activityInstance(blockID: UUID, preparationIndex: Int? = nil) -> WorkoutActivityInstance? {
        activityInstances?.last { $0.blockID == blockID && $0.preparationIndex == preparationIndex }
    }
    func activityElapsedSeconds(instanceID: UUID) -> Int {
        (activityIntervals ?? []).filter { $0.activityInstanceID == instanceID }.reduce(0) { $0 + $1.elapsedSeconds }
    }
    var plannedSeconds: Int { blocks.reduce(0) { $0 + $1.effectiveSeconds + $1.effectiveRestSeconds } }
    var isOpenEnded: Bool { blocks.contains(where: \.isManual) }
    var loggedMinutes: Int {
        if let timerElapsedSeconds { return timerElapsedSeconds / 60 }
        let activeMinutes = blocks.filter { completedBlockIDs.contains($0.id) }.reduce(0) { $0 + $1.minutes }
        let restIDs = Set((blockLogs ?? []).filter { $0.evidenceSource == "rest_timer_elapsed" }.map(\.blockID))
        return activeMinutes + blocks.filter { restIDs.contains($0.id) }.reduce(0) { $0 + $1.restAfterMinutes }
    }
    var elapsedClock: String {
        let seconds = timerElapsedSeconds ?? loggedMinutes * 60
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var completedRoundCount: Int { blocks.filter { $0.kind == .boxing && completedBlockIDs.contains($0.id) }.count }
    var timedRoundCount: Int {
        let boxingIDs = Set(blocks.filter { $0.kind == .boxing }.map(\.id))
        return Set((segmentLogs ?? []).filter {
            boxingIDs.contains($0.blockID) && !$0.isRest && $0.exitReason == "timer_elapsed"
        }.map(\.blockID)).count
    }
    var reachedRoundCount: Int {
        let boxingIDs = Set(blocks.filter { $0.kind == .boxing }.map(\.id))
        return Set((segmentLogs ?? []).filter {
            boxingIDs.contains($0.blockID) && !$0.isRest && $0.elapsedSeconds > 0
        }.map(\.blockID)).count
    }
    func poseEvidence(for blockID: UUID) -> (visible: Int, sampled: Int) {
        let samples = (poseWindows ?? []).filter { $0.blockID == blockID }
        return (samples.filter(\.bodyVisible).count, samples.count)
    }
    var poseLatencyP95Ms: Double? {
        let values = (poseWindows ?? []).compactMap(\.captureToPoseMs).filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !values.isEmpty else { return nil }
        return values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
    }
    var poseUploadEvidence: (selected: Int, acknowledged: Int) {
        let selected = (poseWindows ?? []).filter { $0.uploadLanguage != nil }
        return (selected.count, selected.filter { $0.remoteEventID != nil }.count)
    }
}

enum CampMilestoneKind: String, Codable, CaseIterable { case weighIn, readinessCheck, fightDate, weightClassCampaign }

struct CampMilestone: Codable, Identifiable {
    var id = UUID()
    let kind: CampMilestoneKind
    var date: Date
    var title: String
    var weightClass: String?
    var completedAt: Date?
}

struct WeightRecord: Codable, Identifiable {
    var id = UUID()
    let recordedAt: Date
    let amount: Double
    let unit: String
    let source: String
}

struct TrainingData: Codable {
    var schemaVersion = 1
    var sessions: [TrainingSession] = []
    var milestones: [CampMilestone] = []
    var weightRecords: [WeightRecord]? = []
}

@MainActor final class TrainingStore: ObservableObject {
    @Published private(set) var data = TrainingData()
    @Published var error: String?
    let file: URL
    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = root.appendingPathComponent("TrainingData-v1.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { data = try JSONDecoder().decode(TrainingData.self, from: Data(contentsOf: file)) }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult private func persist() -> Bool {
        do { try JSONEncoder().encode(data).write(to: file, options: .atomic); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func start(_ template: TrainingTemplate, at date: Date = Date(), origin: WorkoutRuntimeOrigin = .current) -> UUID {
        for index in data.sessions.indices where data.sessions[index].state == .active {
            data.sessions[index].state = .interrupted
            data.sessions[index].endedAt = date
            data.sessions[index].endReason = "new_session_started"
        }
        var session = TrainingSession(templateID: template.id, plannedMinutes: template.durationMinutes, createdAt: date, state: .active, blocks: template.blocks)
        session.sourceTitle = template.sourceTitle
        session.sourceURL = template.sourceURL
        session.sourceVersion = template.sourceVersion
        session.startedAt = date
        session.runtimeOrigin = origin
        session.activityInstances = template.blocks.flatMap { WorkoutActivityInstance.initial(for: $0, at: date) }
        session.activityIntervals = []
        session.timerElapsedSeconds = 0
        data.sessions.insert(session, at: 0); persist(); return session.id
    }
    @discardableResult func resumeOrStart(_ template: TrainingTemplate, at date: Date = Date()) -> UUID {
        if let active = data.sessions.first(where: { $0.state == .active }) {
            ensureActivityInstances(sessionID: active.id, at: date)
            return active.id
        }
        return start(template, at: date)
    }
    func ensureActivityInstances(sessionID: UUID, at date: Date = Date()) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active, data.sessions[index].activityInstances == nil else { return }
        data.sessions[index].activityInstances = data.sessions[index].blocks.flatMap {
            WorkoutActivityInstance.initial(for: $0, at: date)
        }
        persist()
    }
    @discardableResult func selectActivity(sessionID: UUID, blockID: UUID, preparationIndex: Int? = nil,
                                          exerciseKey: String?, customName: String? = nil, at date: Date = Date()) -> Bool {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active,
              let block = data.sessions[index].blocks.first(where: { $0.id == blockID }) else { return false }
        let activities = block.activities ?? []
        if activities.isEmpty {
            guard preparationIndex == nil else { return false }
        } else {
            guard let preparationIndex, activities.indices.contains(preparationIndex) else { return false }
        }
        // Extensible stable keys, not source text or model-supplied instructions.
        let key = exerciseKey == "unknown" ? nil : exerciseKey
        let trimmedName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if key == "custom" {
            guard let trimmedName, !trimmedName.isEmpty, trimmedName.count <= 60 else { return false }
        } else if trimmedName != nil { return false }
        if let key {
            guard !key.isEmpty, key.count <= 100,
                  key.unicodeScalars.allSatisfy({ ("a"..."z").contains(String($0)) || ("0"..."9").contains(String($0)) || $0 == "_" }) else { return false }
        }
        ensureActivityInstances(sessionID: sessionID, at: date)
        let provenance: ActivitySelectionProvenance = key == nil ? .unchosen : .userSelected
        if let previous = data.sessions[index].activityInstance(blockID: blockID, preparationIndex: preparationIndex),
           previous.exerciseKey == key, previous.customName == trimmedName, previous.selectionProvenance == provenance { return true }
        data.sessions[index].activityInstances?.append(WorkoutActivityInstance(blockID: blockID,
            preparationIndex: preparationIndex, sourceBlockID: block.sourceBlockID, sourceItemID: block.sourceItemID,
            exerciseKey: key, customName: trimmedName, selectionProvenance: provenance, measurement: .forExercise(key),
            selectedAt: key == nil ? nil : date))
        persist()
        return true
    }
    @discardableResult func recordActivityInterval(sessionID: UUID, blockID: UUID, preparationIndex: Int? = nil,
                                                   activityInstanceID: UUID, cumulativeElapsedSeconds: Int,
                                                   exitReason: ActivityIntervalExitReason, at date: Date = Date()) -> Bool {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active, (0...86400).contains(cumulativeElapsedSeconds),
              date.timeIntervalSince1970 >= 0,
              let block = data.sessions[index].blocks.first(where: { $0.id == blockID }),
              (data.sessions[index].activityIntervals?.count ?? 0) < 2000,
              data.sessions[index].activityInstances?.contains(where: {
                  $0.id == activityInstanceID && $0.blockID == blockID && $0.preparationIndex == preparationIndex
              }) == true else { return false }
        let preparations = block.activities ?? []
        if let preparationIndex {
            guard preparations.indices.contains(preparationIndex),
                  cumulativeElapsedSeconds <= preparations[preparationIndex].minutes * 60 else { return false }
        } else {
            guard preparations.isEmpty, block.isManual || cumulativeElapsedSeconds <= block.effectiveSeconds else { return false }
        }
        let session = data.sessions[index]
        let previousEnd = (session.activityIntervals ?? []).filter {
            $0.blockID == blockID && $0.preparationIndex == preparationIndex
        }.map(\.endElapsedSeconds).max()
        // A pre-upgrade active session has no attributable history. Establish its
        // first boundary without charging old timer seconds to the current choice.
        let baseline = session.activityIntervals == nil
        let start = baseline ? cumulativeElapsedSeconds : (previousEnd ?? 0)
        guard cumulativeElapsedSeconds >= start,
              baseline || cumulativeElapsedSeconds > start else { return false }
        let interval = WorkoutActivityInterval(blockID: blockID, preparationIndex: preparationIndex,
            activityInstanceID: activityInstanceID, startElapsedSeconds: start,
            endElapsedSeconds: cumulativeElapsedSeconds, exitReason: exitReason, closedAt: date, baselineOnly: baseline)
        if data.sessions[index].activityIntervals == nil { data.sessions[index].activityIntervals = [] }
        data.sessions[index].activityIntervals?.append(interval)
        guard persist() else {
            data.sessions[index].activityIntervals = session.activityIntervals
            return false
        }
        return true
    }
    func completeBlock(sessionID: UUID, blockID: UUID, source: String = "boxer_check_in") {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }), data.sessions[index].state == .active,
              data.sessions[index].blocks.contains(where: { $0.id == blockID }),
              !data.sessions[index].completedBlockIDs.contains(blockID) else { return }
        data.sessions[index].completedBlockIDs.append(blockID)
        if data.sessions[index].blockLogs == nil { data.sessions[index].blockLogs = [] }
        data.sessions[index].blockLogs?.append(BlockLog(blockID: blockID, recordedAt: Date(), evidenceSource: source))
        persist()
    }
    func recordRestElapsed(sessionID: UUID, blockID: UUID) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }), data.sessions[index].state == .active,
              data.sessions[index].blocks.contains(where: { $0.id == blockID && $0.restAfterMinutes > 0 }),
              !(data.sessions[index].blockLogs ?? []).contains(where: { $0.blockID == blockID && $0.evidenceSource == "rest_timer_elapsed" }) else { return }
        if data.sessions[index].blockLogs == nil { data.sessions[index].blockLogs = [] }
        data.sessions[index].blockLogs?.append(BlockLog(blockID: blockID, recordedAt: Date(), evidenceSource: "rest_timer_elapsed"))
        persist()
    }
    func recordSegment(sessionID: UUID, blockID: UUID, activityKey: String?, isRest: Bool,
                       plannedSeconds: Int, elapsedSeconds: Int, exitReason: String, at date: Date = Date()) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active,
              let block = data.sessions[index].blocks.first(where: { $0.id == blockID }),
              elapsedSeconds >= 0,
              ["timer_elapsed", "manual_completed", "skipped", "session_finished"].contains(exitReason) else { return }
        let manual = block.isManual && !isRest
        guard manual ? plannedSeconds == 0 : (plannedSeconds > 0 && elapsedSeconds <= plannedSeconds),
              exitReason != "manual_completed" || manual,
              exitReason != "timer_elapsed" || !manual else { return }
        if data.sessions[index].segmentLogs == nil { data.sessions[index].segmentLogs = [] }
        data.sessions[index].segmentLogs?.append(SegmentLog(blockID: blockID, activityKey: activityKey,
            isRest: isRest, plannedSeconds: plannedSeconds, elapsedSeconds: elapsedSeconds,
            exitReason: exitReason, endedAt: date))
        persist()
    }
    func recordPoseWindows(sessionID: UUID, windows: [PoseSampleRecord]) {
        guard !windows.isEmpty,
              let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active else { return }
        let allowed = Set(data.sessions[index].blocks.map(\.id))
        let valid = windows.filter { window in
            allowed.contains(window.blockID) && (0...33).contains(window.landmarkCount)
            && (window.visibleLandmarkCount.map { (0...33).contains($0) && $0 <= window.landmarkCount } ?? true)
            && (window.captureToPoseMs.map { $0.isFinite && (0...10_000).contains($0) } ?? true)
            && (window.wristTravelBodyWidths.map { $0.isFinite && (0...10).contains($0) } ?? true)
        }
        guard !valid.isEmpty else { return }
        if data.sessions[index].poseWindows == nil { data.sessions[index].poseWindows = [] }
        data.sessions[index].poseWindows?.append(contentsOf: valid)
        persist()
    }
    func recordExerciseRep(sessionID: UUID, blockID: UUID, activityKey: String,
                           sourceVersion: String, activityInstanceID: UUID? = nil, at date: Date = Date()) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active,
              let block = data.sessions[index].blocks.first(where: { $0.id == blockID }),
              (activityKey == "squats" && sourceVersion == "mediapipe-squat-angle-v1")
                || (activityKey == "lunges" && sourceVersion == "mediapipe-lunge-angle-v1") else { return }
        if let activityInstanceID {
            guard let instance = data.sessions[index].activityInstances?.first(where: { $0.id == activityInstanceID }),
                  instance.blockID == blockID, instance.exerciseKey == activityKey,
                  instance.measurement.capability == .repCandidate,
                  sourceVersion == instance.measurement.id + "-" + instance.measurement.version,
                  data.sessions[index].activityInstance(blockID: blockID, preparationIndex: instance.preparationIndex)?.id == activityInstanceID else { return }
        } else {
            // Backward-compatible callers retain the original explicit source/preparation authorization.
            guard (block.activities ?? []).contains(where: { $0.key == activityKey }) || block.sourceActivityKey == activityKey else { return }
        }
        guard
              !(data.sessions[index].exerciseReps ?? []).contains(where: {
                  $0.blockID == blockID && $0.activityKey == activityKey
                    && (activityInstanceID == nil || $0.activityInstanceID == activityInstanceID)
                    && date.timeIntervalSince($0.observedAt) < 0.7
              }) else { return }
        if data.sessions[index].exerciseReps == nil { data.sessions[index].exerciseReps = [] }
        data.sessions[index].exerciseReps?.append(ExerciseRepRecord(blockID: blockID,
            activityKey: activityKey, observedAt: date, sourceVersion: sourceVersion, activityInstanceID: activityInstanceID))
        persist()
    }
    func recordEngagementAttempt(sessionID: UUID, attempt: EngagementAttempt) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              let block = data.sessions[index].blocks.first(where: { $0.id == attempt.blockID && $0.kind == .boxing }),
              data.sessions[index].state == .active,
              block.drillID == attempt.protocolID,
              attempt.startMs >= 0, attempt.endMs > attempt.startMs,
              block.isManual || attempt.endMs <= block.effectiveSeconds * 1000,
              ["full", "partial", "unobservable"].contains(attempt.cameraCoverage),
              attempt.spans.allSatisfy({ $0.startMs >= attempt.startMs && $0.endMs <= attempt.endMs && $0.endMs > $0.startMs }),
              !(data.sessions[index].engagementAttempts ?? []).contains(where: { $0.id == attempt.id }) else { return }
        if data.sessions[index].engagementAttempts == nil { data.sessions[index].engagementAttempts = [] }
        data.sessions[index].engagementAttempts?.append(attempt)
        persist()
    }
    func correctEngagementAttempt(sessionID: UUID, attemptID: UUID, note: String, accept: Bool,
                                  at date: Date = Date()) {
        guard let sessionIndex = data.sessions.firstIndex(where: { $0.id == sessionID }),
              let attemptIndex = data.sessions[sessionIndex].engagementAttempts?.firstIndex(where: { $0.id == attemptID }),
              note.count <= 1000 else { return }
        data.sessions[sessionIndex].engagementAttempts?[attemptIndex].boxerCorrection = note
        data.sessions[sessionIndex].engagementAttempts?[attemptIndex].acceptedAt = accept ? date : nil
        persist()
    }
    func recordPoseDelivery(sessionID: UUID, sampleID: UUID, eventID: String) {
        guard UUID(uuidString: eventID) == sampleID,
              let sessionIndex = data.sessions.firstIndex(where: { $0.id == sessionID }),
              let sampleIndex = data.sessions[sessionIndex].poseWindows?.firstIndex(where: { $0.id == sampleID && $0.uploadLanguage != nil }) else { return }
        data.sessions[sessionIndex].poseWindows?[sampleIndex].remoteEventID = eventID
        persist()
    }
    func nextPendingPoseUpload() -> (sessionID: UUID, sample: PoseSampleRecord)? {
        data.sessions.flatMap { session in
            (session.poseWindows ?? []).filter { $0.uploadLanguage != nil && $0.remoteEventID == nil }
                .map { (sessionID: session.id, sample: $0) }
        }.min { $0.sample.sampledAt < $1.sample.sampledAt }
    }
    func recordCueRequest(sessionID: UUID, blockID: UUID, cueKey: String, language: String,
                          trigger: String, at date: Date = Date()) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active,
              let block = data.sessions[index].blocks.first(where: { $0.id == blockID }),
              ["fr", "en"].contains(language),
              ["stage_start", "timer_pacing", "framing"].contains(trigger) else { return }
        let sourcedInstruction = cueKey == "source_instruction" && block.sourceTitle != nil
            && trigger == "stage_start" && language == "en"
        guard sourcedInstruction || TrainingCopy.table[cueKey] != nil || TrainingCopy.base[cueKey] != nil else { return }
        if data.sessions[index].cueRequests == nil { data.sessions[index].cueRequests = [] }
        data.sessions[index].cueRequests?.append(CoachCueRecord(blockID: blockID, requestedAt: date,
                                                                 cueKey: cueKey, language: language, trigger: trigger))
        persist()
    }
    func setDrill(sessionID: UUID, blockID: UUID, drillID: String) {
        guard DrillLibrary.all.contains(where: { $0.id == drillID }),
              let sessionIndex = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[sessionIndex].state == .active,
              let blockIndex = data.sessions[sessionIndex].blocks.firstIndex(where: { $0.id == blockID && $0.kind == .boxing }),
              !data.sessions[sessionIndex].completedBlockIDs.contains(blockID),
              !(data.sessions[sessionIndex].segmentLogs ?? []).contains(where: { $0.blockID == blockID }),
              !(data.sessions[sessionIndex].cueRequests ?? []).contains(where: { $0.blockID == blockID }) else { return }
        data.sessions[sessionIndex].blocks[blockIndex].drillID = drillID
        persist()
    }
    func saveRuntime(sessionID: UUID, segmentIndex: Int, remainingSeconds: Int, elapsedSeconds: Int? = nil) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }), data.sessions[index].state == .active else { return }
        data.sessions[index].runtimeSegmentIndex = max(0, segmentIndex)
        data.sessions[index].runtimeRemainingSeconds = max(0, remainingSeconds)
        if let elapsedSeconds { data.sessions[index].runtimeElapsedSeconds = max(0, elapsedSeconds) }
        persist()
    }
    func recordTimedSeconds(sessionID: UUID, seconds: Int) {
        guard (1...300).contains(seconds),
              let index = data.sessions.firstIndex(where: { $0.id == sessionID }),
              data.sessions[index].state == .active else { return }
        let elapsed = (data.sessions[index].timerElapsedSeconds ?? 0) + seconds
        data.sessions[index].timerElapsedSeconds = data.sessions[index].isOpenEnded
            ? elapsed : min(data.sessions[index].plannedSeconds, elapsed)
        persist()
    }
    func finish(_ id: UUID, reflection: String, at date: Date = Date()) {
        guard let index = data.sessions.firstIndex(where: { $0.id == id }), data.sessions[index].state == .active else { return }
        data.sessions[index].reflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        data.sessions[index].endedAt = date
        data.sessions[index].state = .completed
        let session = data.sessions[index]
        data.sessions[index].completionReceipt = WorkoutCompletionReceipt(
            sessionID: session.id, runtimeOrigin: session.runtimeOrigin ?? .unknown,
            startedAt: session.startedAt, endedAt: date, sourceVersion: session.sourceVersion,
            blocks: session.blocks.map { block in
                return WorkoutCompletionReceipt.Block(blockID: block.id, sourceBlockID: block.sourceBlockID,
                    sourceItemID: block.sourceItemID,
                    completionSources: (session.blockLogs ?? []).filter { $0.blockID == block.id }.map(\.evidenceSource),
                    segments: (session.segmentLogs ?? []).filter { $0.blockID == block.id },
                    cueRequests: (session.cueRequests ?? []).filter { $0.blockID == block.id })
            }, activityInstances: session.activityInstances, activityIntervals: session.activityIntervals)
        persist()
    }
    func nextPendingWorkoutCompletion() -> WorkoutCompletionReceipt? {
        data.sessions.compactMap(\.completionReceipt).filter { $0.remoteEventID == nil }
            .min { $0.endedAt < $1.endedAt }
    }
    func recordWorkoutCompletionDelivery(receiptID: UUID, eventID: String) {
        guard UUID(uuidString: eventID) == receiptID,
              let index = data.sessions.firstIndex(where: { $0.completionReceipt?.id == receiptID }) else { return }
        data.sessions[index].completionReceipt?.remoteEventID = eventID
        persist()
    }
    func updateReflection(_ id: UUID, text: String) {
        guard let index = data.sessions.firstIndex(where: { $0.id == id }),
              data.sessions[index].state == .completed else { return }
        data.sessions[index].reflection = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        persist()
    }
    func linkRound(sessionID: UUID, roundID: UUID) {
        guard let index = data.sessions.firstIndex(where: { $0.id == sessionID }), !data.sessions[index].linkedRoundIDs.contains(roundID) else { return }
        data.sessions[index].linkedRoundIDs.append(roundID); persist()
    }
    func addMilestone(kind: CampMilestoneKind, date: Date, title: String, weightClass: String?) {
        data.milestones.append(CampMilestone(kind: kind, date: date, title: title, weightClass: weightClass?.isEmpty == true ? nil : weightClass))
        data.milestones.sort { $0.date < $1.date }; persist()
    }
    func addWeight(_ amount: Double, unit: String, at date: Date = Date()) {
        guard amount.isFinite, amount > 0, amount < 500, ["kg", "lb"].contains(unit) else { return }
        if data.weightRecords == nil { data.weightRecords = [] }
        data.weightRecords?.insert(WeightRecord(recordedAt: date, amount: amount, unit: unit, source: "boxer_entry"), at: 0)
        persist()
    }
    func sessions(on day: Date, calendar: Calendar = .current) -> [TrainingSession] {
        data.sessions.filter { calendar.isDate($0.startedAt ?? $0.createdAt, inSameDayAs: day) }
    }
}
