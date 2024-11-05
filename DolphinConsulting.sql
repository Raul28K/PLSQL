-- Definicion y asignacion de valores a variables bind
VARIABLE b_fecha VARCHAR2(6);
EXEC :b_fecha := '202106';
VARIABLE b_limite_asig NUMBER;
EXEC :b_limite_asig := 250000;

DECLARE
   -- Definicion cursor principal. Informacipn resumida.
   CURSOR cur_profesion IS 
   SELECT cod_profesion, nombre_profesion
   FROM profesion
   ORDER BY nombre_profesion ASC;
   
   -- Definicion cursor secundario. Informacion detallada.
   CURSOR cur_profesional (p_cod_profesion NUMBER) IS
   SELECT p.numrun_prof, p.dvrun_prof, P.nombre || ' ' || P.appaterno nombre, 
          p.cod_profesion, p.cod_tpcontrato, 
          p.cod_comuna, p.sueldo
   FROM profesional P 
   WHERE p.cod_profesion = p_cod_profesion
  ORDER BY p.cod_profesion, p.appaterno, p.nombre ASC;

-- Definicion variables escalares 
v_msg VARCHAR2(300);
v_msgusr VARCHAR2(300);
v_asig_mov_extra NUMBER(8);
v_porc_asig NUMBER(5,3);
v_asig_prof NUMBER(8);
v_porc_tpcont NUMBER(5,3);
v_asig_tpcont NUMBER(8);
v_asignaciones NUMBER(8) := 0;
v_cantidad_asesorias NUMBER(3);
v_monto_asesorias NUMBER(8);

-- Variables escalares acumuladoras
v_tot_asesorias NUMBER(8);
v_tot_honorarios NUMBER(8);
v_tot_asig_mov NUMBER(8);
v_tot_asig_tpcont NUMBER(8);
v_tot_asig_prof NUMBER(8);
v_tot_asignaciones NUMBER(8); 

-- Definicion Varray para almacenar los porcentajes de asignacion movilizacion extra
TYPE t_varray_porc_mov IS VARRAY(5) OF NUMBER;
varray_porc_mov t_varray_porc_mov;

-- Definicion Excepcion del Usuario para controlar el valor tope de asignaciones
asignacion_limite EXCEPTION;

BEGIN
   -- Truncar tablas y eliminar/crear secuencia
   EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ASIGNACION_MES';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_MES_PROFESION';
   EXECUTE IMMEDIATE 'DROP SEQUENCE SQ_ERROR';
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SQ_ERROR';

   -- Asignacion de valores a varray
   varray_porc_mov:= t_varray_porc_mov(0.02,0.04,0.05,0.07,0.09);

   -- CURSOR QUE LEE LAS PROFESIONES (PRINCIPAL)
   FOR reg_profesion IN cur_profesion LOOP 

       -- Se inicializan las variables totalizadoras en cero  
        v_tot_asesorias:=0;
        v_tot_honorarios:=0;
        v_tot_asig_mov:=0;
        v_tot_asig_tpcont:=0;
        v_tot_asig_prof:=0;
        v_tot_asignaciones:=0;      

       -- CURSOR QUE LEE PROFESIONALES (SECUNDARIO)
       FOR reg_profesional IN cur_profesional (reg_profesion.cod_profesion) LOOP
           
           SELECT NVL(COUNT(a.numrun_prof),0), NVL(SUM(a.honorario),0) 
             INTO v_cantidad_asesorias, v_monto_asesorias
             FROM asesoria a
             WHERE a.numrun_prof=reg_profesional.numrun_prof
              AND to_char(a.inicio_asesoria, 'YYYYMM') = :b_fecha;

           v_asig_mov_extra:=0;

          --Calculo asignacion movilizacion extra
           IF reg_profesional.cod_comuna=82 AND v_monto_asesorias < 350000 THEN 
              v_asig_mov_extra:=ROUND(v_monto_asesorias*varray_porc_mov(1));
           ELSIF reg_profesional.cod_comuna=83 THEN
                 v_asig_mov_extra:=ROUND(v_monto_asesorias*varray_porc_mov(2));
           ELSIF reg_profesional.cod_comuna=85 AND v_monto_asesorias < 400000 THEN
                 v_asig_mov_extra:=ROUND(v_monto_asesorias*varray_porc_mov(3));                   
           ELSIF reg_profesional.cod_comuna=86 AND v_monto_asesorias < 800000 THEN
                 v_asig_mov_extra:=ROUND(v_monto_asesorias*varray_porc_mov(4));   
           ELSIF reg_profesional.cod_comuna=89 AND v_monto_asesorias < 680000 THEN
                 v_asig_mov_extra:=ROUND(v_monto_asesorias*varray_porc_mov(5)); 
           END IF;
           
           -- Calcula asignacion especial profesional
           BEGIN
               SELECT asignacion / 100
               INTO v_porc_asig
               FROM porcentaje_profesion
               WHERE cod_profesion=reg_profesional.cod_profesion;        
           EXCEPTION    
             WHEN OTHERS THEN
                v_msg := SQLERRM;
                v_porc_asig := 0; 
                v_msgusr := 'Error al obtener porcentaje de asignacion para el empleado con run: ' || reg_profesional.numrun_prof;
                INSERT INTO errores_proceso
                VALUES (sq_error.NEXTVAL, v_msg, v_msgusr);
           END;

           v_asig_prof:= ROUND(reg_profesional.sueldo * v_porc_asig);

          -- Calculo asignacion por tipo de contrato
          SELECT incentivo/100
          into v_porc_tpcont  
          from tipo_contrato
          where cod_tpcontrato = reg_profesional.cod_tpcontrato;

          v_asig_tpcont := ROUND(v_monto_asesorias * v_porc_tpcont);

          -- calculamos el total de las asignaciones
          v_asignaciones:=v_asig_mov_extra+v_asig_prof+v_asig_tpcont;

          /* Control Excepcion Predefinida para controlar que el monto de asignaciones no puede ser 
           mayor a $250.000 */
          BEGIN
              IF v_asignaciones > :b_limite_asig THEN
                  RAISE asignacion_limite;  
              END IF;

          EXCEPTION
              WHEN asignacion_limite THEN
                 v_msg := 'Error, el profesional con run: ' || reg_profesional.numrun_prof || ' supera el monto límite de asignaciones';
                    INSERT INTO errores_proceso
                    VALUES (sq_error.NEXTVAL, v_msg,
                           'Se reemplazó el monto total de las asignaciones calculadas de ' ||
                           v_asignaciones || ' por el monto límite de ' ||
                           :b_limite_asig);
                 v_asignaciones := :b_limite_asig;
          END;

          -- INSERCION EN LA TABLA DE DETALLE
          INSERT INTO detalle_asignacion_mes
          VALUES (SUBSTR(:b_fecha,-2),SUBSTR(:b_fecha,1,4),
           reg_profesional.numrun_prof || '-'|| reg_profesional.dvrun_prof,reg_profesional.nombre,
                 reg_profesion.nombre_profesion,
                  v_cantidad_asesorias,v_monto_asesorias,
                  v_asig_mov_extra,v_asig_tpcont,v_asig_prof,v_asignaciones);
                     
         /* SE REALIZA LA SUMATORIA A LAS VARIABLES TOTALIZADORAS QUE SE REQUIEREN PARA INSERTAR
            EN LA TABLA RESUMEN */
          v_tot_asesorias := v_tot_asesorias + v_cantidad_asesorias;
          v_tot_honorarios := v_tot_honorarios + v_monto_asesorias;
          v_tot_asig_mov := v_tot_asig_mov + v_asig_mov_extra;
          v_tot_asig_tpcont := v_tot_asig_tpcont + v_asig_tpcont;
          v_tot_asig_prof := v_tot_asig_prof + v_asig_prof;
          v_tot_asignaciones:= v_tot_asignaciones + v_asignaciones;
          
       END LOOP;
       
       -- INSERCION EN LA TABLA DE RESUMEN
       INSERT INTO resumen_mes_profesion
       VALUES (:b_fecha, reg_profesion.nombre_profesion,v_tot_asesorias,v_tot_honorarios,
              v_tot_asig_mov, v_tot_asig_tpcont,v_tot_asig_prof,v_tot_asignaciones); 
   END LOOP;
   COMMIT;
END;  
