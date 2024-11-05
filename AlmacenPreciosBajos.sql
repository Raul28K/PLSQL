--Almacén “Precios Bajos”

VARIABLE b_fecha_proceso VARCHAR2(10);
VAR b_valor_cf NUMBER;
EXEC :b_fecha_proceso:='31/05/2021';
EXEC :b_valor_cf:=6300;

-- Se declaran variables para ejecucion de LOOP y cálculo de valores solicitados
DECLARE
v_min_id_ven NUMBER(3);
v_max_id_ven NUMBER(3);
v_pct_afp NUMBER(3);
v_pct_salud NUMBER(3);
v_rut_vend NUMBER(10);
v_sueldo_base NUMBER(8);
v_fec_cont DATE;
v_annos NUMBER;
v_porc_antig NUMBER(2);
v_porc_categ NUMBER(4,3);
v_id_categ VARCHAR2(2);
v_tot_cargas NUMBER;
v_asig_antig NUMBER(8):=0;
v_bono_categ NUMBER(8):=0;
v_asig_cargas NUMBER(8):=0;
v_com_ventas  NUMBER(8);
v_total_desctos NUMBER(10);
v_total_haberes NUMBER(10) := 0;
v_monto_afp NUMBER(10) := 0;
v_monto_salud NUMBER(10) := 0;
v_id_afp NUMBER(1);
v_id_salud NUMBER(1);

BEGIN
   -- Truncamos las tablas para facilitar la ejecucion del bloque
   EXECUTE IMMEDIATE('TRUNCATE TABLE HABER_MES_VENDEDOR');
   EXECUTE IMMEDIATE('TRUNCATE TABLE DESCUENTO_MES_VENDEDOR');

      -- Se obtienen las id minima y maxima para recorrer la tabla vendedor y se asignan los valores a las variables definidas
   SELECT MIN(id_vendedor), MAX(id_vendedor) INTO v_min_id_ven, v_max_id_ven FROM vendedor;
   
   -- While Loop para recorrer los id de vendedores
   WHILE  v_min_id_ven <= v_max_id_ven
   LOOP
     -- Se inicializan las variables asignacion de antiguedad y bono de categoria, ya que si no cumplen
     -- con la condicion de los IF donde su utilizan, la variable quedará con el valor que se asigno
     -- en un empleado anterior. 
     v_asig_antig:=0;
     v_bono_categ:=0;
     -- Obtiene los datos basicos para el proceso
      SELECT v.rut_vendedor, v.fec_contrato, v.sueldo_base, v.id_categoria, 
             ROUND(MONTHS_BETWEEN(:b_fecha_proceso,v.fec_contrato)/12),
             v.id_afp, v.id_salud
      INTO v_rut_vend, v_fec_cont, v_sueldo_base, v_id_categ, v_annos, 
           v_id_afp, v_id_salud
      FROM vendedor v 
      WHERE v.id_vendedor = v_min_id_ven;
      
      -- Calcula bonificacion por antiguedad
      IF v_annos > 0 THEN
           SELECT porc_bonif
             INTO v_porc_antig
             FROM bonificacion_antig
            WHERE v_annos BETWEEN anno_tramo_inf AND anno_tramo_sup;
            v_asig_antig:=ROUND(v_sueldo_base*(v_porc_antig/100));
      END IF;

     -- Obtiene el numero de cargas y calcula la asignacion por cargas
     SELECT COUNT(*)
     INTO v_tot_cargas
     FROM carga_familiar
     WHERE id_vendedor = v_min_id_ven;

     -- Calculo el valor de la asignacion
     v_asig_cargas := ROUND(:b_valor_cf * v_tot_cargas);
     
     -- Calculo monto de comisiones del mes y anno de proceso   
     SELECT NVL(SUM(monto_comision),0) --Si es NULL, entrega 0.
     INTO v_com_ventas
     FROM comision_venta
     WHERE id_vendedor = v_min_id_ven
       AND anno= SUBSTR(:b_fecha_proceso,7) --Si no indico fin, toma todos los caracteres a partir de la posición 7
       AND mes=SUBSTR(:b_fecha_proceso,5,1);
       
      -- C�lculo bono especial por categoria 
      IF v_id_categ IN ('A', 'B') THEN 
           SELECT porcentaje/100
             INTO v_porc_categ
             FROM categoria
            WHERE id_categoria = v_id_categ;

            v_bono_categ:=ROUND(v_com_ventas*v_porc_categ);
      END IF;

     -- Calculo total de los haberes
     v_total_haberes := v_sueldo_base + v_asig_antig + v_asig_cargas + v_com_ventas + v_bono_categ;


    --Los descuentos por concepto de afp y salud se aplican sobre el total de los haberes calculado.
    SELECT AFP.PORC_DESCTO_AFP
    INTO v_pct_afp
    FROM AFP 
    WHERE ID_AFP = v_id_afp;

    SELECT SALUD.PORC_DESCTO_SALUD
    INTO v_pct_salud
    FROM SALUD
    WHERE ID_SALUD = v_id_salud;

    v_monto_afp:= ROUND(v_total_haberes*(v_pct_afp/100));
    v_monto_salud:= ROUND(v_total_haberes*(v_pct_salud/100));

    /*El total de descuentos de un vendedor corresponderá al descuento de salud + descuento de afp.*/
    v_total_desctos:=v_monto_afp+v_monto_salud;
    
    -- INSERCION DE LOS RESULTADOS EN LAS TABLAS    
    INSERT INTO haber_mes_vendedor
    VALUES(v_min_id_ven, v_rut_vend, SUBSTR(:b_fecha_proceso,5,1), 
           SUBSTR(:b_fecha_proceso,7),v_sueldo_base,
           v_asig_antig,v_asig_cargas, v_com_ventas, 
           v_bono_categ,v_total_haberes);
    
    INSERT INTO DESCUENTO_MES_VENDEDOR
    VALUES(v_min_id_ven, v_rut_vend, SUBSTR(:b_fecha_proceso,5,1),
           SUBSTR(:b_fecha_proceso,7),v_monto_salud,
           v_monto_afp,v_total_desctos);
    COMMIT;
    --Aumento el valor del ID mínimo para consultar al siguiente vendedor en la próxima iteración
    v_min_id_ven := v_min_id_ven + 10;      
   END LOOP;
END;