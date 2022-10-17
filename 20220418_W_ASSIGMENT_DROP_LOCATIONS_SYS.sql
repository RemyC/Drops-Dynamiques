create or replace PROCEDURE	W_ASSIGMENT_DROP_LOCATIONS_SYS IS
--DECLARE

-- RemyCarpentier 2022-04 

counter_tir 	INTEGER; 									--Compteur Tir
counter_drop 	INTEGER; 									--Compteur Drop
counter_drop_2 	INTEGER; 									--Compteur entre 1 a nbtotal_drop, <> counter_drop
counter_expe	INTEGER;									--Compteur du nombre d'expé dans un curseur
counter_expe2   INTEGER;                        			--Compteur du nombre d'expé dans un curseur bis
i               INTEGER;                        			--Variable quelconque mais utile
nbtotal_drop 	INTEGER; 									--Compteur Nb total DROP
consolidation 	varchar2(200); 								--Max 100 Drops
v_currDrop      varchar2(7);								--Variable contenant le locn_id du drop
v_currDrop_dsp  varchar2(20);                               --Variable contenant le dsp_locn du drop
v_currDrop_area varchar2(10);								--Variable contenant la Area du drop
v_currDrop_zone varchar2(10);								--Variable contenant la Zone du drop
v_listDrop SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(); 	--"Liste/Dictionnaire" contenant tous les locn_id des drops du code systeme

BEGIN

dbms_output.put_line ('Start    : '||sysdate);
counter_drop := 1;
nbtotal_drop := 0; --init avec 0 drop d'active
i := 0;
v_listDrop.extend(4); --!!Hardcode!! Sur 4 Drops

--Recupere les infos du code systeme (liste des drops et nb de tirs) et les stocks en SYS.ODCIVARCHAR2LIST()
FOR drops_init IN (
    SELECT code_id, misc_flags FROM whse_sys_code wsc210 WHERE wsc210.rec_type='C' AND wsc210.code_type='W17' ORDER BY code_id
    ) LOOP
	i := i +1;
    SELECT locn_id INTO v_currDrop FROM locn_hdr WHERE dsp_locn = drops_init.code_id;
    v_listDrop(i) := v_currDrop;
	nbtotal_drop := nbtotal_drop+1;
END LOOP drops_init;

--**********************************************************
dbms_output.put_line ('INITIALISATION ...');
dbms_output.put_line ('Nb Drops : '||nbtotal_drop);
dbms_output.put_line ('____________________________________________');
--dbms_output.put_line ('Noms des Drops : '|| v_listDrop);
--**********************************************************

--##########################################################################################################################
--########################################################################################################################## 

BEGIN		--METTRE A JOUR LA VUE MATERIALISE POUR AVOIR LES OLPNS ACTUELS
 --**********************************************************
dbms_output.put_line ('Init Refresh View Start : '||sysdate);
 --**********************************************************
DBMS_MVIEW.REFRESH('c_udom_dshb_assigm_drop_loc');
 --**********************************************************
dbms_output.put_line ('Init Refresh View End   : '||sysdate);
dbms_output.put_line ('____________________________________________');
--**********************************************************
END;

--##########################################################################################################################
--########################################################################################################################## 

--Boucle sur les drops parametres dans le code systeme associe
counter_drop := 0;
FOR drops IN (
    SELECT code_id, misc_flags FROM whse_sys_code wsc210 WHERE wsc210.rec_type='C' AND wsc210.code_type='W17' ORDER BY code_id 
    ) LOOP
    counter_drop := counter_drop+1;
	--**********************************************************
	dbms_output.put_line (drops.code_id||' >> Nb Tirs : '||drops.misc_flags);
	--**********************************************************

    --Recupere les infos du drop actuel (directement, puis stocker dans varchar2)
    SELECT locn_id, dsp_locn, area, zone INTO v_currDrop, v_currDrop_dsp, v_currDrop_area, v_currDrop_zone FROM locn_hdr WHERE dsp_locn = drops.code_id;
	--**********************************************************
    dbms_output.put_line('    '||'Locn_id:'||v_currDrop ||', Area:'|| v_currDrop_area ||', Zone:'|| v_currDrop_zone);
	--**********************************************************

    --##########################################################################################################################
	--##########################################################################################################################

    DECLARE 	--LIBERER LES TIRS DES EXPEDITIONS QUI NE SONT PLLUS ELIGIBLES

	CURSOR cursor_ExpeSansOlpnAvecTir is
		SELECT DISTINCT vue.expe as ship, vue.tir as tir, vue.heure_depart
		FROM c_udom_dshb_assigm_drop_loc vue
		WHERE 1 = 1
		--Drop actuel
		AND vue.N_drop = v_currDrop_dsp
		--0 OLPN sur le drop et 0 OLPN en cour de prep a destination du drop
		AND vue.support is null
		--L'expe est affectee a une tir
		AND coalesce(substr(vue.tir,counter_drop*2-1, 2),'00') <> '00'
		--Tri par heure de depart croissant
		ORDER BY vue.heure_depart
    ;

	BEGIN		--LIBERER LES TIRS DES EXPEDITIONS QUI NE SONT PLLUS ELIGIBLES

 	--**********************************************************
	dbms_output.put_line('    '||'1.  Curseurs          : OK');
	--**********************************************************

	counter_expe := 0;
	FOR chargement_0 IN cursor_ExpeSansOlpnAvecTir LOOP
        -- Compter le nombre de ligne dans le curseur ExpeAvecOlpnAvecTir
		counter_expe := counter_expe +1;
        --**********************************************************
        --dbms_output.put_line('    '||'1.. '||chargement_0.ship);
        --**********************************************************
	END LOOP chargement_0;	
    --**********************************************************
    --dbms_output.put_line(counter_expe);
    --dbms_output.put_line('    '||'1.. Tirs a libr/Total : '||counter_expe||'/'||drops.misc_flags);
    --**********************************************************

    i :=0;
	-- Tester si le nb d'expe affectees = nb tir disponibles
	IF counter_expe > 0 THEN		-- Des tirs sont a desaffecter
		--Pour tous les chargements dans ce curseur, mettre a jour s.loc_reference avec '00'
		FOR chargement_1 IN cursor_ExpeSansOlpnAvecTir LOOP
			--dbms_output.put_line('        '||'Non eligible : '||chargement_1.ship||' '||chargement_1.tir);
			counter_drop_2 := 0;
			consolidation := null; 							-- Variable de texte a mettre dans le champ s.loc_reference		
			FOR counter_drop_2 IN 1..nbtotal_drop LOOP 		-- Boucle sur tous les drops du code systeme
				IF counter_drop_2 = counter_drop THEN		-- Pour le drop actuel >> mettre '00'
					consolidation := consolidation || '00';
				ELSE 										-- Pour les autres drops, laisser les tirs affectees
					consolidation := consolidation ||  coalesce(substr('00'||substr(chargement_1.tir,counter_drop_2*2-1, 2), -2), '00');
				END IF;
			END LOOP counter_drop_2;
			--**********************************************************
			dbms_output.put_line('        '||'Tir liberee  : '||chargement_1.ship||' '||chargement_1.tir||' >> '||consolidation);
			--**********************************************************
			-- Mise a jour du champ S.loc_reference avec la valeur de consolidation
			UPDATE shipment S SET S.loc_reference = consolidation WHERE S.tc_shipment_id = chargement_1.ship;
			i := i +1;
		END LOOP chargement_1;
		COMMIT;

		BEGIN		--METTRE A JOUR LA VUE MATERIALISE POUR ACTUALISER LES TIRS LIBEREES
		--**********************************************************
		dbms_output.put_line ('____________________________________________');
		dbms_output.put_line ('1st Refresh View Start  : '||sysdate);
		--**********************************************************
		DBMS_MVIEW.REFRESH ('c_udom_dshb_assigm_drop_loc');
		--**********************************************************
		dbms_output.put_line ('1st Refresh View End    : '||sysdate);
		dbms_output.put_line ('____________________________________________');
		--**********************************************************
		END;
        
        --**********************************************************
        dbms_output.put_line('    '||'1.. Nb Tirs liberees  : '||i);
        --**********************************************************
    ELSE
        --**********************************************************
        dbms_output.put_line('    '||'1.. Pas de liberation ...');
        --**********************************************************
	END IF;



	END;		--LIBERER LES TIRS DES EXPEDITIONS QUI NE SONT PLLUS ELIGIBLES

--##########################################################################################################################
--##########################################################################################################################

	DECLARE		--VERIFIER ET AFFECTER LES TIRS LIBRES AUX EXPEDITIONS ELIGIBLES

    TYPE vtype      IS TABLE OF VARCHAR2 (10);
    v_listAll       vtype := vtype ();  --Liste de toutes les tirs selon le code systeme 
    v_listUsed      vtype := vtype ();  --Liste des tirs utilisees par une expe
    v_listNotUsed   vtype := vtype ();  --Liste des tirs non utilisees, donc libres
    listNotUsed     varchar(255);       --Texte des tirs non utilisees

	CURSOR cursor_ExpeAvecOlpnAvecTir is
		SELECT DISTINCT vue.expe as ship, vue.tir as tir
		FROM c_udom_dshb_assigm_drop_loc vue
		WHERE 1 = 1
		--Drop actuel 
		AND vue.N_drop = v_currDrop_dsp
		--Au moins 1 OLPN sur le drop ou 1 OLPN en cour de prep a destination du drop
		AND vue.support is NOT null
		--L'expe est affectee a une tir
		AND coalesce(substr(vue.tir,counter_drop*2-1, 2),'00') <> '00'
		--Tri par numero de tir croissant
		ORDER BY substr(vue.tir,counter_drop*2-1, 2)
    ;

	CURSOR cursor_ExpeAvecOlpnSansTir is
		SELECT DISTINCT vue.expe as ship, vue.tir as tir, vue.heure_depart
		FROM c_udom_dshb_assigm_drop_loc vue
		WHERE 1 = 1
		--Drop actuel
		AND vue.N_drop = v_currDrop_dsp
		--Au moins 1 OLPN sur le drop ou 1 OLPN en cour de prep a destination du drop
		AND vue.support is NOT null
		--L'expe est affectee a une tir
		AND coalesce(substr(vue.tir,counter_drop*2-1, 2),'00') = '00'
		--Tri par heure de depart croissant
		ORDER BY vue.heure_depart
    ;

	BEGIN		--VERIFIER ET AFFECTER LES TIRS LIBRES AUX EXPEDITIONS ELIGIBLES

    --**********************************************************
    dbms_output.put_line('    '||'2.  Curseurs          : OK');
    --********************************************************** 

	counter_expe := 0;
	FOR chargement_2 IN cursor_ExpeAvecOlpnAvecTir LOOP
        -- Compter le nombre de ligne dans le curseur ExpeAvecOlpnAvecTir
		counter_expe := counter_expe +1;
        --**********************************************************
        --dbms_output.put_line('    '||'2..  Chargements affectes '||chargement_2.ship||' >> '||chargement_2.tir);
        --**********************************************************
	END LOOP chargement_2;	
    --**********************************************************
    dbms_output.put_line('    '||'2.. Tirs affect/Total : '||counter_expe||'/'||drops.misc_flags);
    --**********************************************************

	-- Tester si le nb d'expe affectees = nb tir disponibles
	IF counter_expe <> drops.misc_flags THEN		-- Des tirs ne sont pas affectees et sont donc disponibles

        --Remplir v_listAll de 01 au nb de tir selon le code systeme	
        v_listAll.extend(drops.misc_flags);
        FOR counter_tir IN 1..drops.misc_flags LOOP
            v_listAll(counter_tir) := substr('00'||counter_tir, -2);
            --**********************************************************
            --dbms_output.put_line('        '||v_listAll(counter_tir));
            --**********************************************************
        END LOOP counter_tir;

        -- Constituer la liste des Tirs deja utilisees (v_listUsed), si non vide et <> '00'
        i:=1;
        v_listUsed.extend(counter_expe);
        FOR chargement_3 IN cursor_ExpeAvecOlpnAvecTir LOOP
            IF  coalesce(substr('00'||substr(chargement_3.tir,counter_drop*2-1, 2), -2), '00') > '00' THEN
                v_listUsed(i) := substr('00'||substr(chargement_3.tir,counter_drop*2-1, 2), -2);
                --**********************************************************
                --dbms_output.put_line('        '||v_listUsed(i));
                --**********************************************************
                i := i+1;
            END IF;
        END LOOP chargement_3;

        --Faire la difference entre les deux listes V_listAll et v_listUsed et mettre le resultat dans v_listNotUsed
        v_listNotUsed.extend(drops.misc_flags-counter_expe);
        v_listNotUsed := v_listAll MULTISET EXCEPT v_listUsed;
        FOR i IN v_listNotUsed.first .. v_listNotUsed.last LOOP
            listNotUsed := listNotUsed ||', '||v_listNotUsed(i);
        END LOOP i ;
        --**********************************************************
        --dbms_output.put_line('        '||to_char(drops.misc_flags-counter_expe)||' Tirs dispo : '||substr(listNotUsed, 3, 252));
        --**********************************************************

        --Compte le nombre de lignes dans cursor_ExpeAvecOlpnSansTir
        counter_tir := 1;
        counter_expe2 := 0;
        FOR chargement_4 in cursor_ExpeAvecOlpnSansTir LOOP
            counter_expe2 := counter_expe2 +1;
            --**********************************************************
            --dbms_output.put_line('        '||'Expe a affectees : '||chargement_4.ship||' >> '||chargement_4.tir);
            --**********************************************************
        END LOOP chargement_4;    
        --**********************************************************
        --dbms_output.put_line('        '||'Nb Expe a affectees : '||counter_expe2);
        --dbms_output.put_line('        '||'v_currDrop     :'||v_currDrop);
        --dbms_output.put_line('        '||'v_currDrop_Area:'||v_currDrop_area);
        --dbms_output.put_line('        '||'v_currDrop_Zone:'||v_currDrop_zone);
        --dbms_output.put_line('        '||'v_listDrop     :'||v_listDrop);
        --dbms_output.put_line('        '||'counter_drop   :'||counter_drop);
        --**********************************************************

        --Affecte les premiers lignes de cursor_ExpeAvecOlpnSansTir aux tirs de v_listNotUsed
        FOR chargement_5 IN cursor_ExpeAvecOlpnSansTir LOOP
            --dbms_output.put_line('        '||'Expe : '||chargement_5.ship||' '||chargement_5.tir);
            counter_drop_2 := 0;
            consolidation := null;                          -- Variable de texte a mettre dans le champ s.loc_reference
            FOR counter_drop_2 in 1 .. nbtotal_drop LOOP 	-- Boucle sur tous les drops du code systeme                
                IF counter_drop_2 = counter_drop THEN		-- Pour le drop actuel >> mettre '00'
                    consolidation := consolidation || v_listNotUsed(counter_tir);
                ELSE 										-- Pour les autres drops, laisser les tirs affectees
                    consolidation := consolidation || coalesce(substr('00'||substr(chargement_5.tir,counter_drop_2*2-1, 2), -2), '00');
                END IF;
            END LOOP counter_drop_2;
            --**********************************************************
            dbms_output.put_line('        '||'Expe : '||chargement_5.ship||' '||coalesce(chargement_5.tir, 'null')||' >> '||consolidation);
            --**********************************************************

            -- Mise a jour du champ S.loc_reference avec la valeur de consolidation
            UPDATE shipment S SET S.loc_reference = consolidation WHERE S.tc_shipment_id = chargement_5.ship;
            counter_tir := counter_tir + 1;
            --Quitte la boucle FOR une fois que toutes les liges de v_listNotUsed sont parcourues
            EXIT WHEN counter_tir > v_listNotUsed.count;
        END LOOP chargement_5;
		COMMIT;

		BEGIN		--METTRE A JOUR LA VUE MATERIALISE POUR ACTUALISER LES SCI
		--**********************************************************
		dbms_output.put_line ('____________________________________________');
		dbms_output.put_line ('2nd Refresh View Start  : '||sysdate);
		--**********************************************************
		DBMS_MVIEW.REFRESH ('c_udom_dshb_assigm_drop_loc');
		--**********************************************************
		dbms_output.put_line ('2nd Refresh View End    : '||sysdate);
		dbms_output.put_line ('____________________________________________');
		--**********************************************************
		END;

	END IF;

    i := least(to_number(v_listNotUsed.count), to_number(counter_expe2));
    --**********************************************************
    dbms_output.put_line ('    '||'2...'||'Nb Tirs libres    : '||v_listNotUsed.count);
    IF v_listNotUsed.count = 0 THEN 
        dbms_output.put_line ('    '||'    '||'Pas d''affectation ...');
    ELSE
        dbms_output.put_line ('    '||'    '||'Nb Expe libres    : '||coalesce(counter_expe2,0));
        dbms_output.put_line ('    '||'    '||'Nb d''affectation  : '||coalesce(i,0));
    END IF;
	dbms_output.put_line ('============================================');
	--**********************************************************
	END;		--VERIFIER ET AFFECTER LES TIRS LIBRES AUX EXPEDITIONS ELIGIBLES

END LOOP drops;

--##########################################################################################################################
--########################################################################################################################## 

--**********************************************************
dbms_output.put_line ('End    : '||sysdate);
dbms_output.put_line ('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
dbms_output.put_line ('~~~~~~       That''s all folks !       ~~~~~~');
dbms_output.put_line ('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
--**********************************************************

END;