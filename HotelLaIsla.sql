/* Cree una tabla adicional para manejar violacion de PK, aca la estructura
CREATE TABLE TEMP_SALIDAS_DIARIAS_HUESPEDES (
  id_huesped NUMBER,
  nombre VARCHAR2(50),
  procedencia VARCHAR2(50),
  alojamiento NUMBER,
  consumos NUMBER,
  tours NUMBER,
  subtotal_pago NUMBER,
  descuento_consumos NUMBER,
  descuentos_procedencia NUMBER,
  total NUMBER);
*/

--CREACION PACKAGE
CREATE OR REPLACE PACKAGE PKG_CONSUMO IS
FUNCTION FN_OBT_CONS(p_id_huesped NUMBER) RETURN NUMBER;
v_monto_consumo NUMBER(20);
END PKG_CONSUMO;
/
CREATE OR REPLACE PACKAGE BODY PKG_CONSUMO IS
FUNCTION FN_OBT_CONS (p_id_huesped NUMBER) RETURN NUMBER IS
BEGIN
    SELECT nvl(tc.monto_consumos,0)
      INTO v_monto_consumo
      FROM TOTAL_CONSUMOS tc       
     WHERE tc.id_huesped = p_id_huesped;
     RETURN v_monto_consumo;
END FN_OBT_CONS;
END PKG_CONSUMO;
/
--CREACION FUNCION PARA OBTENER LA PROCEDENCIA
CREATE OR REPLACE FUNCTION FN_PROCEDENCIA(p_id_huesped NUMBER) RETURN VARCHAR2 IS
v_lugar_procedencia VARCHAR2(100);
v_msgerr VARCHAR2 (100);
BEGIN 
    SELECT p.nom_procedencia
    INTO v_lugar_procedencia
    FROM HUESPED h 
    JOIN PROCEDENCIA p ON h.id_procedencia = p.id_procedencia
    WHERE h.id_huesped = p_id_huesped;
    RETURN v_lugar_procedencia;
    EXCEPTION
        WHEN OTHERS THEN 
        v_msgerr := SQLERRM;
        INSERT INTO ERRORES_PROCESO
        VALUES ( SQ_ERROR.nextval, 'No se registra procedencia para el huesped:'||p_id_huesped||'.',v_msgerr);
        RETURN ('NO REGISTRA PROCEDENCIA');     
END FN_PROCEDENCIA;

--CREACION FUNCION PARA CALCULO DE TOURS
CREATE OR REPLACE FUNCTION FN_TOURS(p_id_huesped NUMBER) RETURN NUMBER IS
v_monto_tours NUMBER(20);
BEGIN
    BEGIN
    SELECT nvl(SUM(t.valor_tour),0)
    INTO v_monto_tours
    FROM HUESPED_TOUR ht 
    JOIN TOUR t ON ht.id_tour = t.id_tour
    WHERE ht.id_huesped = p_id_huesped
    GROUP BY ht.id_huesped;
    
    IF v_monto_tours IS NULL THEN 
    v_monto_tours:= 0;
    END IF;
    
    EXCEPTION
    WHEN NO_DATA_FOUND THEN
      v_monto_tours := 0;
    END;
  RETURN v_monto_tours;
END FN_TOURS;

--CREACION DE PROCEDIMIENTO PRINCIPAL
CREATE OR REPLACE PROCEDURE SP_CALCULO_PAGOS(p_fecha_proceso DATE , p_dolar NUMBER) IS
    v_id_huesped NUMBER;
    v_nombre_huesped VARCHAR2(50);
    v_procedencia VARCHAR2(50);
    v_alojamiento NUMBER;
    v_consumos NUMBER;
    v_tours NUMBER;
    v_subtotal NUMBER;
    v_pct_dcto_cons NUMBER;
    v_dcto_cons NUMBER; 
    v_dcto_proc NUMBER;
    v_total NUMBER;

    CURSOR cur_huesped IS
    SELECT hue.id_huesped, 
           hue.nom_huesped,
           hue.appat_huesped,
           hue.apmat_huesped,
           hue.id_procedencia,
           r.ingreso,
           r.estadia,
           dr.id_habitacion,
           hab.valor_habitacion,
           hab.valor_minibar
    FROM huesped hue
    JOIN reserva r ON hue.id_huesped = r.id_huesped
    JOIN detalle_reserva dr ON r.id_reserva = dr.id_reserva
    JOIN habitacion hab ON dr.id_habitacion = hab.id_habitacion
    WHERE p_fecha_proceso = r.ingreso + r.estadia;
    
    reg_huespedes cur_huesped%ROWTYPE;
 BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE SALIDAS_DIARIAS_HUESPEDES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';
    
    IF NOT cur_huesped%ISOPEN THEN
        OPEN cur_huesped;
    END IF;
    
    LOOP
        FETCH cur_huesped INTO reg_huespedes;
        EXIT WHEN cur_huesped%NOTFOUND;
        
        --ID y NOMBRE
        v_id_huesped := reg_huespedes.id_huesped;
        v_nombre_huesped := reg_huespedes.nom_huesped || ' ' || reg_huespedes.appat_huesped || ' ' || reg_huespedes.apmat_huesped;
        
        --PROCEDENCIA
        v_procedencia := FN_PROCEDENCIA(reg_huespedes.id_huesped);
    
        --ALOJAMIENTO
        v_alojamiento := (p_dolar*((reg_huespedes.valor_habitacion*reg_huespedes.estadia) 
                          + (reg_huespedes.valor_minibar*reg_huespedes.estadia)));
                          
        --CONSUMO
        v_consumos := (p_dolar*PKG_CONSUMO.FN_OBT_CONS(reg_huespedes.id_huesped));
        
        --TOURS
        v_tours := (p_dolar*FN_TOURS(reg_huespedes.id_huesped));
        
        --Subtotal
        v_subtotal := v_alojamiento + v_consumos + v_tours;
        
        --Dcto Consumo
        BEGIN
        SELECT r.PCT
        INTO v_pct_dcto_cons
        FROM RANGOS_CONSUMOS r
        WHERE v_consumos BETWEEN r.vmin_tramo AND r.vmax_tramo;
        
        v_dcto_cons := v_consumos*v_pct_dcto_cons;        
        EXCEPTION
        WHEN NO_DATA_FOUND THEN
        v_pct_dcto_cons := 0;
        v_dcto_cons := 0;
        END;        
        --Dcto Procedencia
        IF v_procedencia = 'ISLA DE MAN' THEN
        v_dcto_proc := 0.1 * v_subtotal;
        ELSIF v_procedencia IN ('LIECHTENSTEIN', 'PAISES BAJOS') THEN
        v_dcto_proc := 0.2 * v_subtotal;
        ELSE
        v_dcto_proc := 0;
        END IF;       
        
        --Total
        v_total := (v_subtotal - (v_dcto_cons + v_dcto_proc));

        --TABLA TEMPORAL UTILIZADA PARA EVITAR PROBLEMAS CON VIOLACION DE PK
        INSERT INTO TEMP_SALIDAS_DIARIAS_HUESPEDES (
        id_huesped, nombre, procedencia, alojamiento, consumos, tours, subtotal_pago, descuento_consumos, descuentos_procedencia, total) 
        VALUES (
        v_id_huesped, v_nombre_huesped, v_procedencia, v_alojamiento, v_consumos, v_tours, v_subtotal, v_dcto_cons, v_dcto_proc, v_total);
      END LOOP;
      CLOSE cur_huesped;
      
INSERT INTO SALIDAS_DIARIAS_HUESPEDES (
    id_huesped, nombre, procedencia, alojamiento, consumos, tours, subtotal_pago, descuento_consumos, descuentos_procedencia, total
  )
  SELECT id_huesped, 
         MAX(nombre), 
         MAX(procedencia), 
         SUM(alojamiento), 
         MAX(consumos), 
         MAX(tours), 
         MAX(subtotal_pago), 
         MAX(descuento_consumos), 
         MAX(descuentos_procedencia), 
         MAX(total)
  FROM TEMP_SALIDAS_DIARIAS_HUESPEDES
  GROUP BY id_huesped;
  
  -- Limpiar la tabla temporal despues de la consolidacion
  EXECUTE IMMEDIATE 'TRUNCATE TABLE TEMP_SALIDAS_DIARIAS_HUESPEDES';
END SP_CALCULO_PAGOS;

--TRIGGER PARA ACTUALIZAR LA TABLA HUESPED X REGION
CREATE OR REPLACE TRIGGER TRG_ACT_HUESPED_REGION
AFTER INSERT ON SALIDAS_DIARIAS_HUESPEDES
FOR EACH ROW
DECLARE
    v_nom_region VARCHAR2(100);    
BEGIN
    BEGIN
    SELECT r.nom_region
    INTO v_nom_region
    FROM procedencia p
    JOIN region r ON p.id_region = r.id_region
    WHERE p.nom_procedencia = :NEW.procedencia;
    
    UPDATE huespedes_por_region huer
    SET cantidad = cantidad + 1
    WHERE huer.nombre_region = v_nom_region;
    
    EXCEPTION
    WHEN NO_DATA_FOUND THEN
    UPDATE huespedes_por_region 
    SET cantidad = cantidad;
    END;
END;

--EJECUTANTE DEL PROCEDIMIENTO
EXEC SP_CALCULO_PAGOS(TO_DATE('16/10/2020', 'DD/MM/YYYY'), 890)
