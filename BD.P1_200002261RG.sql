VAR b_fecha_proc DATE;
EXEC :b_fecha_proc := 11/04/2024;
VAR b_fecha_vig  DATE;
EXEC :b_fecha_vig := 19/04/2024;

DECLARE
v_nmo_postulacion NUMBER;
v_nmo_postulacion_min NUMBER;
v_nmo_postulacion_max NUMBER;
v_nombre_cliente postulacion.nombre%TYPE;
v_annos NUMBER;
v_ptje_antiguedad NUMBER;
v_sueldo_liq NUMBER;
v_ptje_sueldoliq NUMBER;
v_id_prof profesion.id_profesion%TYPE;
v_id_prof_min profesion.id_profesion%TYPE;
v_id_prof_max profesion.id_profesion%TYPE;
v_ptje_prof NUMBER;
v_id_estadociv NUMBER;
v_id_estadociv_min NUMBER;
v_id_estadociv_max NUMBER;
v_ptje_estadociv NUMBER;
v_ptje_total NUMBER;
v_pdcto_selec VARCHAR2;


BEGIN
--TRUNCAMOS TABLA
EXECUTE IMMEDIATE 'TRUNCATE TABLE RESULTADO_CUENTA';
--GUARDAMOS EL NMO DE POSTULACION 
SELECT NUMERO_POSTULACION
INTO v_nmo_postulacion
FROM POSTULACION;
--GUARDAMOS LOS NMOS DE POSTULACION MIN Y MAX
SELECT MIN(NUMERO_POSTULACION),MAX(NUMERO_POSTULACION)
INTO v_nmo_postulacion_min,v_nmo_postulacion_max
FROM POSTULACION;


--Para procesar cada una de las solicitudes
    WHILE v_nmo_postulacion <= v_nmo_postulacion_max LOOP
--Para Obtener nombre
        SELECT (p.nombre||" "||p.materno||" "||p.paterno)
        INTO v_nombre_cliente
        FROM POSTULACION p;
--Para obtener Puntaje x antiguedad
        SELECT  ROUND(MONTHS_BETWEEN(b_fecha_proc,p.FECHA_INICIO_TRABAJO)/12)
        INTO v_annos
        FROM POSTULACION p;
        IF v_annos >0 THEN
            SELECT a.PUNTAJE
            INTO v_ptje_antiguedad
            FROM ANTIGUEDAD a
            WHERE v_annos BETWEEN antiguedad_min AND antiguedad_max;
        END IF;
--Para obtener Puntaje x sueldo
        SELECT  ROUND(p.sueldo_bruto*0,83)
        INTO v_sueldo_liq
        FROM POSTULACION p;
        IF v_sueldo_liq > 0 THEN
            SELECT s.PUNTAJE
            INTO v_ptje_sueldoliq
            FROM SUELDO_LIQ s 
            WHERE v_annos BETWEEN s.sueldo_min AND s.sueldo_max;
        END IF;        
--Para obtener Puntaje x profesion
    SELECT MIN(pr.ID_PROFESION),MAX(pr.ID_PROFESION)
    INTO v_id_prof_min,v_id_prof_max
    FROM PROFESION pr;
        SELECT  p.id_profesion
        INTO v_id_prof
        FROM POSTULACION p;
        IF v_id_prof > 0  THEN
            SELECT pr.PUNTAJE
            INTO v_ptje_prof
            FROM PROFESION pr 
            WHERE v_id_prof BETWEEN v_id_prof_min AND v_id_prof_max;
        END IF;        
--Para obtener Puntaje x estado civil 
    SELECT MIN(ec.id_estado_civil),MAX(ec.id_estado_civil)
    INTO v_id_estadociv_min,v_id_estadociv_max
    FROM ESTADO_CIVIL ec;
        SELECT  ec.id_estado_civil
        INTO v_id_estadociv
        FROM ESTADO_CIVIL ec;
        IF v_id_estadociv >0 THEN
            SELECT ec.PUNTAJE
            INTO v_ptje_estadociv
            FROM ESTADO_CIVIL ec
            WHERE v_id_estadociv BETWEEN v_id_estadociv_min AND v_id_estadociv_max;
        END IF;  
    v_ptje_total:=(v_ptje_antiguedad+v_ptje_sueldoliq+v_ptje_prof);
    INSERT INTO RESULTADO_CUENTA(NUMERO_POSTULACION,FECHA_PROCESO,FECHA_VIGENCIA_INFORME,NOMBRE_POSTULANTE,PUNTAJE_ANTIGUEDAD,
                PUNTAJE_SUELDO,PUNTAJE_PROFESION,PUNTAJE_CIVIL,TOTAL_PUNTAJE)
    VALUES(v_nmo_postulacion,b_fecha_proc,b_fecha_vig,v_nombre_cliente,v_ptje_antiguedad,v_ptje_sueldoliq,v_ptje_prof,
           v_ptje_estadociv,v_ptje_total);
    COMMIT;   
    --INCREMENTA EL ID EN 1 PARA RECORRER
    v_nmo_postulacion:=(v_nmo_postulacion+1);
    END LOOP; 
END;

