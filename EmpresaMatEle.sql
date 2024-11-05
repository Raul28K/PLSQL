SET SERVEROUTPUT ON;

CREATE USER MDY3131_PRUEBAEJEMPLO3 IDENTIFIED BY "MDY3131.pruebaejemplo_3"
DEFAULT TABLESPACE "USERS"
TEMPORARY TABLESPACE "TEMP";
ALTER USER MDY3131_PRUEBAEJEMPLO3 QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION TO MDY3131_PRUEBAEJEMPLO3;
GRANT "RESOURCE" TO MDY3131_PRUEBAEJEMPLO3;
ALTER USER MDY3131_PRUEBAEJEMPLO3 DEFAULT ROLE "RESOURCE";

GRANT CREATE SESSION, CREATE VIEW, CREATE TABLE, ALTER SESSION, CREATE SEQUENCE TO MDY3131_PRUEBAEJEMPLO3;
GRANT CREATE SYNONYM, CREATE DATABASE LINK, RESOURCE, UNLIMITED TABLESPACE TO MDY3131_PRUEBAEJEMPLO3;

ALTER SESSION DISABLE PARALLEL DML;
ALTER SESSION DISABLE PARALLEL DDL;
ALTER SESSION DISABLE PARALLEL query;

DROP sequence SEQ_ERROR;
create sequence SEQ_ERROR;

--Package
CREATE OR REPLACE PACKAGE PKG_VENTAS IS
    V_TOTAL_VENTAS NUMBER;
    FUNCTION F_TOTAL_VENTAS(P_RUN_EMPLEADO VARCHAR2,P_FECHA_PROCESO DATE) RETURN NUMBER;
    PROCEDURE P_GRABAR_ERROR(P_RUTINA_ERROR VARCHAR2, P_MENSAJE_ERROR VARCHAR2);
END PKG_VENTAS;

CREATE OR REPLACE PACKAGE BODY PKG_VENTAS IS
    -- funcion que retorna el monto total de las ventas
    FUNCTION F_TOTAL_VENTAS(p_run_empleado VARCHAR2, p_fecha_proceso DATE) RETURN NUMBER IS
        /*cursor que lee tabla boleta, para obtener el total de ventas del empleado, la seleccion que genera el cursor es filtrada
        para el mes y año en que se esta ejecutando el proceso y por el rut del empleado que se esta procesando.
        */
        CURSOR cur_boleta IS SELECT * FROM BOLETA WHERE 
        EXTRACT(MONTH FROM p_fecha_proceso) = EXTRACT(MONTH FROM BOLETA.FECHA)
        AND EXTRACT(YEAR FROM P_FECHA_PROCESO) = EXTRACT(YEAR FROM BOLETA.FECHA)
        AND p_run_empleado = boleta.run_empleado;
        BEGIN
            --Se inicializa la vari
            v_total_ventas := 0;
            FOR reg_boleta IN cur_boleta LOOP
                v_total_ventas := v_total_ventas + reg_boleta.monto_total_boleta;
            END LOOP;
            
            IF v_total_ventas > 0 THEN
                RETURN v_total_ventas;
            ELSE
                RETURN 0;
            END IF;
    END F_TOTAL_VENTAS;
    /*procedimiento para insertar los errores que se produzcan al obtener los porcentajes para calcular la
    asignacion especial por antiguedad y la asignacion por escolaridad*/
    PROCEDURE P_GRABAR_ERROR(p_rutina_error VARCHAR2, p_mensaje_error VARCHAR2) IS
        BEGIN
            INSERT INTO ERROR_CALC
            VALUES(SEQ_ERROR.NEXTVAL,p_rutina_error,p_mensaje_error);
    END P_GRABAR_ERROR;
END PKG_VENTAS;

CREATE OR REPLACE PACKAGE BODY PKG_VENTAS IS
    -- funcion que retorne el monto total de las ventas
  FUNCTION F_TOTAL_VENTAS(P_RUN_EMPLEADO VARCHAR2,P_FECHA_PROCESO DATE) RETURN NUMBER IS
    --Variable que se utilizara la retornar el total de ventas de cada empleado
    V_VENTAS NUMBER;
    /*cursor que lee tabla boleta, para obtener el total de ventas del empleado, la seleccion que genera el cursor es filtrada
    para el mes y anno en que se esta ejecutando el proceso y por el rut del empleado que se esta procesando.*/
    CURSOR CUR_BOLETA IS SELECT * FROM BOLETA WHERE
    EXTRACT(MONTH FROM P_FECHA_PROCESO) = EXTRACT(MONTH FROM BOLETA.FECHA)
    AND EXTRACT(YEAR FROM P_FECHA_PROCESO) = EXTRACT(YEAR FROM BOLETA.FECHA)
    AND P_RUN_EMPLEADO = BOLETA.RUN_EMPLEADO;
    BEGIN
        --Se inicializa la variable ventas para comenzar en cero.
        V_VENTAS := 0;
        --Se recorre el cursor boleta para obtener el monto total de la boleta de cada venta del vendedor procesado.
        FOR REG_BOLETA IN CUR_BOLETA LOOP
            V_VENTAS := V_VENTAS + REG_BOLETA.MONTO_TOTAL_BOLETA;
        END LOOP;
        
        RETURN V_VENTAS;
        
        --Opcion alternativa donde se valida si v_ventas es >0, para en caso contrario retornar cero
        /*V_VENTAS := 0;
        FOR REG_BOLETA IN CUR_BOLETA LOOP
            V_VENTAS := V_VENTAS + REG_BOLETA.MONTO_TOTAL_BOLETA;
        END LOOP;
        
        /*IF V_VENTAS > 0 THEN
            RETURN V_VENTAS;
        ELSE
            RETURN 0;
        END IF;*/
        */
    /*procedimiento para insertar los errores que se produzcan al obtener los porcentajes para calcular la
    asignacion especial por antiguedad y la asignacion por escolaridad*/
    PROCEDURE P_GRABAR_ERROR(p_rutina_error VARCHAR2, p_mensaje_error VARCHAR2) IS
        BEGIN
            INSERT INTO ERROR_CALC
            VALUES(SEQ_ERROR.NEXTVAL,p_rutina_error,p_mensaje_error);
    END P_GRABAR_ERROR;
  END F_TOTAL_VENTAS;

--Funcion que retorne el porcentaje por antiguedad que le corresponde al empleado segun los annos que lleva trabajando en la empresa
--Recibe como parametro el rut de empleado para obtener los datos del empleado que se esta procesando y fecha de proceso para calcular la 
--antiguedad a la fecha de proceso
CREATE OR REPLACE FUNCTION FN_ANTIGUEDAD
(p_run_empleado VARCHAR2,p_fecha_proceso DATE) RETURN NUMBER IS
--Variable para almacenar los annos de antiguedad del empleado que se esta procesando
v_antiguedad NUMBER;
--Variable para almacenar el porcentaje de antiguedad que retornara la funcion
v_porc_antiguedad NUMBER;

BEGIN   
        SELECT ROUND(MONTHS_BETWEEN(p_fecha_proceso,empleado.fecha_contrato)/12)
        INTO v_antiguedad
        FROM empleado
        WHERE p_run_empleado = run_empleado;

        SELECT porc_antiguedad/100
        INTO v_porc_antiguedad
        FROM porcentaje_antiguedad
        WHERE v_antiguedad BETWEEN annos_antiguedad_inf AND annos_antiguedad_sup;
    
        RETURN v_porc_antiguedad;

        EXCEPTION
        WHEN OTHERS THEN
            PKG_VENTAS.P_GRABAR_ERROR('Error en la función FN ANTIGUEDAD al obtener el porcentaje asociado a '||v_antiguedad||
            ' años de antiguedad',SQLERRM);
            RETURN 0;
END FN_ANTIGUEDAD;

--Funcion que retorne el porcentaje por antiguedad que le corresponde al empleado segun los annos que lleva trabajando en la empresa
--Recibe como parametro el rut de empleado para obtener los datos del empleado que se esta procesando
CREATE OR REPLACE FUNCTION FN_ESCOLARIDAD
(p_run_empleado   VARCHAR2) RETURN NUMBER IS
--Variable para almacenar el codigo de escolaridad del empleado que se esta procesando
v_cod_escolaridad NUMBER;
--Variable para almacenar el porcentaje de escolaridad que retornara la funcion
v_porc_escolaridad NUMBER;

BEGIN   
        SELECT cod_escolaridad
        INTO v_cod_escolaridad
        FROM empleado
        WHERE p_run_empleado = run_empleado;

        SELECT porc_escolaridad/100
        INTO v_porc_escolaridad
        FROM porcentaje_escolaridad
        WHERE v_cod_escolaridad = cod_escolaridad;

        RETURN v_porc_escolaridad;

        EXCEPTION
        WHEN OTHERS THEN
            PKG_VENTAS.P_GRABAR_ERROR('Error en la funcion FN ESCOLARIDAD al obtener el porcentaje asociado al codigo escolaridad '
            ||v_cod_escolaridad,SQLERRM);
            RETURN 0;
END FN_ESCOLARIDAD;


--Trigger que genera la informacion de la tabla CALIFICACION_MENSUAL_EMPLEADO
CREATE OR REPLACE TRIGGER TRG_CALIFICACION_MENSUAL
--Luego de cada insercion en la tabla DETALLE_HABERES_MENSUAL, para cada fila, se validara en que tramo se calificacion se encuentra el
--empleado y se generara la calificacion correspondiente.
AFTER INSERT ON DETALLE_HABERES_MENSUAL
FOR EACH ROW
DECLARE
--variable para almacenar la calificacion del empleado.
V_CALIFICACION VARCHAR2(200);
BEGIN
    --Validacion de tramo de calificacion en que se encuentra el empleado con base en el total de haberes. Se utiliza :NEW, porque se estan
    --leyendo las inserciones recien realizadas en la tabla DETALLE_HABERES_MENSUAL, por lo tanto, son valores nuevos.
    IF :NEW.TOTAL_HABERES BETWEEN 400000 AND 700000 THEN
        V_CALIFICACION := 'Total de Haberes: '||:NEW.TOTAL_HABERES||'. Califica como Empleado con Salario Bajo el 
        Promedio';
    ELSIF :NEW.TOTAL_HABERES BETWEEN 700001 AND 900000 THEN
        V_CALIFICACION := 'Total de Haberes: '||:NEW.TOTAL_HABERES||'. Califica como Empleado con Salario Promedio';
    ELSIF :NEW.TOTAL_HABERES > 900000 THEN
        V_CALIFICACION := 'Total de Haberes: '||:NEW.TOTAL_HABERES||'. Califica como Empleado con Salario Sobre el 
        Promedio';
    END IF;

    --Por cada fila, se insertan los valores nuevos leidos desde la tabla DETALLE_HABERES_MENSUAL y la calificacion generada en la tabla 
    --CALIFICACION_MENSUAL_EMPLEADO
    INSERT INTO CALIFICACION_MENSUAL_EMPLEADO(MES, ANNO, RUN_EMPLEADO, 
    TOTAL_HABERES, CALIFICACION)
    VALUES (:NEW.MES, :NEW.ANNO, :NEW.RUN_EMPLEADO, 
    :NEW.TOTAL_HABERES,V_CALIFICACION);
END;

-- Procedimiento almacenado principal para efectuar el calculo de los haberes de las remuneraciones de los empleados de la empresa
-- El procedimiento debe recibir como parametro la fecha de proceso, valor de colacion y valor de movilizacion
CREATE OR REPLACE PROCEDURE SP_DETALLE_HABERES(p_fecha_proceso date, p_valor_colacion NUMBER, p_valor_movilizacion NUMBER)
IS
    --Cursor que lee la tabla empleados completa
    CURSOR cur_empleado IS SELECT * FROM empleado;
    --Variables para almacenar el valor de comision por ventas que se calculara en el procedimiento almacenado
    v_por_comision_ventas NUMBER;
BEGIN
    --Se deben truncar en tiempo de ejecucion las tablas en que se insertaran datos durante la ejecucion del proceso
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_HABERES_MENSUAL';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE CALIFICACION_MENSUAL_EMPLEADO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_CALC';
    
    --Se lee el cursor empleado para obtener la informacion de cada uno
    FOR reg_empleado IN cur_empleado LOOP
        
        BEGIN
        --Se obtiene el porcentaje de comision por ventas de cada empleado, de acuerdo con el total de ventas que retorna la funcion
        -- F_TOTAL_VENTAS del package pkg_ventas
        SELECT porc_comision/100
        INTO v_por_comision_ventas
        FROM porcentaje_comision_venta
        WHERE pkg_ventas.F_TOTAL_VENTAS(reg_empleado.run_empleado,p_fecha_proceso) BETWEEN venta_inf AND venta_sup;

        -- Manejo de errores al obtener el porcentaje de comision por ventas, en caso de que ocurra este error, el valor de comision por ventas
        -- es cero
        EXCEPTION
        WHEN OTHERS THEN
            v_por_comision_ventas := 0;
        END;

        --Se insertaron los valors obtener en la tabla DETALLE_HABERES_MENSUAL
        INSERT INTO DETALLE_HABERES_MENSUAL

        VALUES (
                --Mes en que se ejecuta el proceso
                TO_NUMBER(EXTRACT(MONTH FROM p_fecha_proceso),'99'),
                --Anno en que se ejecuta el proceso
                TO_NUMBER(EXTRACT(YEAR FROM p_fecha_proceso),'9999'),
                --rut del empleado
                reg_empleado.run_empleado,
                --nombre del empleado
                reg_empleado.nombre||' '||reg_empleado.paterno||' '||reg_empleado.materno,
                --sueldo base del empleado
                reg_empleado.sueldo_base,
                --asignacion de colacion, que se recibe como parametro del procedimiento almacenado
                p_valor_colacion,
                --asignacion de movilizacion, que se recibe como parametro del procedimiento almacenado.
                p_valor_movilizacion,
                --bonificacion por antiguedad, calculada a partir del total de ventas del empleado y el porcentaje de antiguedad respectivo
                pkg_ventas.F_TOTAL_VENTAS(reg_empleado.run_empleado,p_fecha_proceso)*FN_ANTIGUEDAD(reg_empleado.run_empleado,p_fecha_proceso),
                --bonificacion por escolaridad, calculada a partir del sueldo base del empleado y el porcentaje de escolaridad respectivo
                reg_empleado.sueldo_base*FN_ESCOLARIDAD(reg_empleado.run_empleado),
                --comision por ventas, calculada a partir del total de ventas del empleado y el porcentaje de comision respectivo
                pkg_ventas.F_TOTAL_VENTAS(reg_empleado.run_empleado,p_fecha_proceso)*v_por_comision_ventas,
                --total de haberes corresponde a la suma del sueldo base del empleado + colacion + movilizacion + asignacion por annos 
                --trabajados + comision por ventas + asignacion por escolaridad.
                reg_empleado.sueldo_base + p_valor_colacion + p_valor_movilizacion + 
                pkg_ventas.F_TOTAL_VENTAS(reg_empleado.run_empleado,p_fecha_proceso)*FN_ANTIGUEDAD(reg_empleado.run_empleado,p_fecha_proceso) + 
                reg_empleado.sueldo_base*FN_ESCOLARIDAD(reg_empleado.run_empleado) + 
                pkg_ventas.F_TOTAL_VENTAS(reg_empleado.run_empleado,p_fecha_proceso)*v_por_comision_ventas);   
    END LOOP;
END;

--Ejecución con parámetros de entrada solicitados; fecha de proceso, asignacion de colacion y asignacion de movilizacion.
EXEC SP_DETALLE_HABERES('30/06/2022',75000,60000);