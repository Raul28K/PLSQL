--CREACION PACKAGE PARA PUNTAJES
CREATE OR REPLACE PACKAGE PKG_PUNTAJES IS
FUNCTION FN_OBT_PTJE_ZONAEXT(p_id_postulante NUMBER) RETURN NUMBER;
FUNCTION FN_OBT_PTJE_INST(p_id_postulante NUMBER) RETURN NUMBER;
v_zonaext NUMBER (20);
v_ptje_zonaext NUMBER(20);
v_rank_inst NUMBER(20);
v_ptje_inst NUMBER(20);
END PKG_PUNTAJES;

CREATE OR REPLACE PACKAGE BODY PKG_PUNTAJES IS
--FUNCION PARA OBTENER EL PUNTAJE DE ZONA EXTREMA
FUNCTION FN_OBT_PTJE_ZONAEXT (p_id_postulante NUMBER) RETURN NUMBER IS
BEGIN
    SELECT nvl(ss.zona_extrema,0)
      INTO v_zonaext
      FROM ANTECEDENTES_LABORALES al   
      JOIN SERVICIO_SALUD ss ON al.cod_serv_salud = ss.cod_serv_salud
     WHERE al.numrun= p_id_postulante;
     
     SELECT nvl(pze.ptje_zona,0)
     INTO v_ptje_zonaext
     FROM PTJE_ZONA_EXTREMA pze
     WHERE pze.zona_extrema = v_zonaext;
     RETURN v_ptje_zonaext;
END FN_OBT_PTJE_ZONAEXT;

--FUNCION PARA OBTENER EL PUNTAJE POR RANKING DE LA INSTITUCION
FUNCTION FN_OBT_PTJE_INST(p_id_postulante NUMBER) RETURN NUMBER IS
BEGIN 
    SELECT nvl(i.ranking,0)
    INTO v_rank_inst
    FROM POSTULACION_PROGRAMA_ESPEC ppe
    JOIN PROGRAMA_ESPECIALIZACION pe ON ppe.cod_programa = pe.cod_programa
    JOIN INSTITUCION i ON pe.cod_inst = i.cod_inst
    WHERE ppe.numrun = p_id_postulante;

    SELECT nvl(pr.ptje_ranking,0)
    INTO v_ptje_inst
    FROM PTJE_RANKING_INST pr
    WHERE v_rank_inst BETWEEN pr.RANGO_RANKING_INI AND pr.RANGO_RANKING_TER;
    RETURN v_ptje_inst;
END FN_OBT_PTJE_INST;

END PKG_PUNTAJES;

--CREACION FUNCION PARA OBTENER PUNTAJE POR LA CANTIDAD DE HORAS QUE TRABAJA EL POSTULANTE
CREATE OR REPLACE FUNCTION FN_OBT_PTJE_HORAS(p_id_postulante NUMBER) RETURN NUMBER IS
v_cant_horas NUMBER(20);
v_ptje_horas NUMBER(20);
v_msgerr VARCHAR2 (100);
BEGIN 
    SELECT nvl(SUM(al.horas_semanales),0)
    INTO v_cant_horas
    FROM ANTECEDENTES_LABORALES al 
    WHERE al.numrun = p_id_postulante
    GROUP BY al.numrun;
    
    BEGIN
        SELECT pht.ptje_horas_trab
        INTO v_ptje_horas
        FROM PTJE_HORAS_TRABAJO pht
        WHERE v_cant_horas BETWEEN pht.rango_horas_ini and pht.rango_horas_ter;
        RETURN v_ptje_horas;
        EXCEPTION
            WHEN OTHERS THEN 
            v_msgerr := SQLERRM;
            INSERT INTO ERROR_PROCESO
            VALUES ( p_id_postulante, 'Error en FN_OBT_PTJE_HORAS al obtener el puntaje con horas de trabajo semanal: '||v_cant_horas||'.',v_msgerr);
            RETURN 0;  
    END;
END FN_OBT_PTJE_HORAS;

--CREACION FUNCION PARA OBTENER PUNTAJE POR LOS AÑOS DE EXPERIENCIA 
CREATE OR REPLACE FUNCTION FN_OBT_PTJE_ANNOS(p_id_postulante NUMBER) RETURN NUMBER IS
v_contrato_ant DATE;
v_cant_annos NUMBER(20);
v_ptje_annos NUMBER(20);
v_msgerr VARCHAR2(100);
BEGIN
    SELECT MIN(al.fecha_contrato)
    INTO v_contrato_ant
    FROM ANTECEDENTES_LABORALES al 
    WHERE al.numrun = p_id_postulante
    GROUP BY al.numrun;
    
    v_cant_annos:=(MONTHS_BETWEEN(SYSDATE,v_contrato_ant)/12);
    BEGIN
        SELECT pae.ptje_experiencia
        INTO v_ptje_annos
        FROM PTJE_ANNOS_EXPERIENCIA pae
        WHERE v_cant_annos BETWEEN pae.rango_annos_ini AND pae.rango_annos_ter;
        RETURN v_ptje_annos;
        EXCEPTION
            WHEN OTHERS THEN 
            v_msgerr := SQLERRM;
            INSERT INTO ERROR_PROCESO
            VALUES ( p_id_postulante, 'Error en FN_OBT_PTJE_ANNOS al obtener el puntaje con años de experiencia: '||v_cant_annos||'.',v_msgerr);
            RETURN 0;
     END;   
END FN_OBT_PTJE_ANNOS;
    
    

--CREACION DE PROCEDIMIENTO PRINCIPAL PARA GENERAR LA INFO DE LOS POSTULANTES 
CREATE OR REPLACE PROCEDURE SP_POSTULANTES_BECA(p_fecha_proceso DATE , p_pct_esp_1 NUMBER, p_pct_esp_2 NUMBER) IS
    v_id_postulante NUMBER;
    v_nombre_postulante VARCHAR2(50);
    v_ptje_annos_postulante NUMBER(20);
    v_ptje_horas_postulante NUMBER(20);
    v_ptje_zonaext_postulante NUMBER(20);
    v_ptje_ranking_postulante NUMBER(20);
    v_ptje_espc_1_postulante NUMBER (20);
    v_ptje_espc_2_postulante NUMBER (20);
    v_ptje_subtotal NUMBER(20);
    v_edad_postulante NUMBER(20);
    v_cant_annos_postulante NUMBER(20);
    v_cant_horas_postulante NUMBER(20);
    

    CURSOR cur_postulante IS
    SELECT ap.numrun,
           ap.pnombre,
           ap.snombre,
           ap.apaterno,
           ap.amaterno,
           ap.fecha_nacimiento,
           MIN(al.fecha_contrato) as fecha_contrato,
           SUM(al.horas_semanales) as horas_semanales
    FROM ANTECEDENTES_PERSONALES ap
    JOIN ANTECEDENTES_LABORALES al ON ap.numrun = al.numrun
    GROUP BY ap.numrun, ap.pnombre, ap.snombre, ap.apaterno, ap.amaterno, ap.fecha_nacimiento
    ORDER BY ap.numrun ASC;
    
    reg_postulantes cur_postulante%ROWTYPE;
    
 BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTAJE_POSTULACION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_PROCESO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESULTADO_POSTULACION';
    
    IF NOT cur_postulante%ISOPEN THEN
        OPEN cur_postulante;
    END IF;
    
    LOOP
        FETCH cur_postulante INTO reg_postulantes;
        EXIT WHEN cur_postulante%NOTFOUND;
        
        --ID y NOMBRE
        v_id_postulante := reg_postulantes.numrun;
        v_nombre_postulante := reg_postulantes.pnombre || ' ' ||reg_postulantes.snombre||' ' || reg_postulantes.apaterno || ' ' || reg_postulantes.amaterno;
        
        --PUNTAJE POR AÑOS DE EXPERIENCIA
        v_ptje_annos_postulante := FN_OBT_PTJE_ANNOS(reg_postulantes.numrun);
    
        --PUNTAJE POR LA CANTIDAD DE HORAS SEMANALES QUE TRABAJA
        v_ptje_horas_postulante := FN_OBT_PTJE_HORAS(reg_postulantes.numrun);
                          
        --PUNTAJE POR TRABAJAR EN ZONA EXTREMA
        v_ptje_zonaext_postulante := PKG_PUNTAJES.FN_OBT_PTJE_ZONAEXT(reg_postulantes.numrun);
        
        --PUNTAJE POR RANKING DE LA INSTITUCION
        v_ptje_ranking_postulante:= PKG_PUNTAJES.FN_OBT_PTJE_INST(reg_postulantes.numrun);
               
        --CALCULO DE SUBTOTAL DE PUNTAJES, EDAD, AÑOS DE EXPERIENCIA Y HORAS TRABAJADAS PARA CALCULO DE PUNTAJES ESPECIALES
        v_ptje_subtotal:=v_ptje_annos_postulante + v_ptje_horas_postulante + v_ptje_zonaext_postulante;
        v_edad_postulante:= FLOOR(MONTHS_BETWEEN(p_fecha_proceso, reg_postulantes.fecha_nacimiento) / 12);
        v_cant_annos_postulante:= FLOOR(MONTHS_BETWEEN(p_fecha_proceso, reg_postulantes.fecha_contrato) / 12);
        v_cant_horas_postulante:= reg_postulantes.horas_semanales;
        
        --PUNTAJE ESPECIAL 1. TENER MAS DE 45 Y TRABAJAR MAS DE 30 HRS.       
        IF v_edad_postulante < 45 AND v_cant_horas_postulante > 30 THEN 
            v_ptje_espc_1_postulante:= v_ptje_subtotal * p_pct_esp_1;
        ELSE
            v_ptje_espc_1_postulante:= 0;
        END IF;
        
        --PUNTAJE ESPECIAL 2. TENER MÁS DE 25 AÑOS DE EXPERIENCIA
        
        IF v_cant_annos_postulante > 25 THEN 
            v_ptje_espc_2_postulante:= v_ptje_subtotal *  p_pct_esp_2;
        ELSE
            v_ptje_espc_2_postulante:= 0;
        END IF; 
        
        --INSERCIÓN DE LOS CALCULOS DE LOS POSTULANTES EN LA TABLA DETALLE.
        INSERT INTO DETALLE_PUNTAJE_POSTULACION (
        RUN_POSTULANTE, NOMBRE_POSTULANTE, PTJE_ANNOS_EXP, PTJE_HORAS_TRAB, PTJE_ZONA_EXTREMA, PTJE_RANKING_INST, PTJE_EXTRA_1, PTJE_EXTRA_2) 
        VALUES (
        v_id_postulante, v_nombre_postulante, v_ptje_annos_postulante, v_ptje_horas_postulante, v_ptje_zonaext_postulante,v_ptje_ranking_postulante,v_ptje_espc_1_postulante,v_ptje_espc_2_postulante);
      END LOOP;
      CLOSE cur_postulante;
END SP_POSTULANTES_BECA;

--TRIGGER PARA ACTUALIZAR LA TABLA HUESPED X REGION
CREATE OR REPLACE TRIGGER TRG_ACT_RESULTADO_POST
AFTER INSERT ON DETALLE_PUNTAJE_POSTULACION
FOR EACH ROW
DECLARE
    v_ptje_total NUMBER(20);
    v_resultado_postulacion VARCHAR2(100);    
BEGIN
    v_ptje_total := :NEW.PTJE_ANNOS_EXP + :NEW.PTJE_HORAS_TRAB + :NEW.PTJE_ZONA_EXTREMA + :NEW.PTJE_RANKING_INST + :NEW.PTJE_EXTRA_1 + :NEW.PTJE_EXTRA_2;

    IF v_ptje_total >= 4500 THEN
        v_resultado_postulacion := 'SELECCIONADO';
    ELSE
        v_resultado_postulacion := 'NO SELECCIONADO';
    END IF;

    INSERT INTO RESULTADO_POSTULACION (run_postulante, ptje_final_post, resultado_post)
    VALUES (:NEW.RUN_POSTULANTE, v_ptje_total, v_resultado_postulacion);
END TRG_ACT_RESULTADO_POST;



--EJECUTANTE DEL PROCEDIMIENTO
EXEC SP_POSTULANTES_BECA(TO_DATE('30/06/2023', 'DD/MM/YYYY'), 0.3, 0.15);