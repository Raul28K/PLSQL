VARIABLE b_mes VARCHAR2(6);
EXEC :b_mes := '05';
VARIABLE b_anno VARCHAR2(6);
EXEC :b_anno := '2021';
VARIABLE b_limite_com NUMBER;
EXEC :b_limite_com := 16000;

DECLARE
   -- Definicion cursor principal. Informacion resumida.
   CURSOR cur_categoria_res IS 
   SELECT ID_CATEGORIA, NOM_CATEGORIA
   FROM CATEGORIA
   ORDER BY NOM_CATEGORIA ASC;
   
   -- Definicion cursor secundario. Informacion detallada.
   CURSOR cur_categoria_det (c_id_categoria NUMBER) IS
   SELECT v.fec_venta,COUNT(v.id_venta) cantidad,
          SUM(d.cantidad*p.precio) total, 
          p.id_categoria, c.nom_categoria nomcateg                       
   FROM VENTA v 
    join DETALLE_VENTA d ON v.id_venta= d.id_venta
    join PRODUCTO p ON d.id_producto= p.id_producto
    join CATEGORIA c ON p.id_categoria= c.id_categoria
   WHERE c.id_categoria=c_id_categoria AND
    EXTRACT(MONTH FROM v.fec_venta)= :b_mes AND
    EXTRACT(YEAR FROM v.fec_venta)= :b_anno
  GROUP BY v.fec_venta
  ORDER BY v.fec_venta;

-- Deficion variables escalares 
v_msg VARCHAR2(300);
v_msgusr VARCHAR2(300);
v_fec_venta VARCHAR2(300);
v_nombre_cat VARCHAR2(300);
v_num_ventas VARCHAR2(300);
v_monto_ventas VARCHAR2(300);

-- Variables escalares acumuladoras
v_impto NUMBER(8);
v_pct_impto NUMBER(8);
v_dcto_cat NUMBER(5,3);
v_com NUMBER(8);
v_pct_com NUMBER(8);
v_deliv NUMBER(5,3);
v_total_dctos NUMBER(8);
v_total_ventas NUMBER(8);
v_num_ventas_total NUMBER(10);
v_monto_ventas_total NUMBER(10);
v_impto_total NUMBER(10);
v_dcto_cat_total NUMBER(10);
v_com_total NUMBER(10);
v_deliv_total NUMBER(10);
v_total_dctos_total NUMBER(10);
v_total_ventas_total NUMBER(10);


-- Definicion Varray para almacenar los descuentos por categoria
TYPE t_varray_dcto_cat IS VARRAY(5) OF NUMBER;
varray_dcto_cat t_varray_dcto_cat;
TYPE t_varray_deliv IS VARRAY(1) OF NUMBER;
varray_deliv t_varray_deliv;
-- Definicion Excepcion del Usuario para controlar el valor tope de la comision
comision_limite EXCEPTION;

BEGIN
   -- Truncar tablas y eliminar - crear secuencia
   EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_CATEGORIA';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_CATEGORIA';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_PROCESO';
   EXECUTE IMMEDIATE 'DROP SEQUENCE SQ_ERROR';
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SQ_ERROR';

   -- Asignacion de valores a varray
   varray_dcto_cat:= t_varray_dcto_cat(0.19,0.17,0.15,0.13,0.11);
   varray_deliv:= t_varray_deliv(1500);
   
   
   -- CURSOR QUE LEE LAS CATEGORIAS (PRINCIPAL)
   FOR reg_categorias IN cur_categoria_res LOOP 

       -- Se inicializan las variables totalizadoras en cero  
        v_impto :=0;
        v_pct_impto:=0;
        v_dcto_cat :=0;
        v_com :=0;
        v_pct_com:=0;
        v_deliv :=0;
        v_total_dctos :=0;
        v_total_ventas :=0;     

       -- CURSOR QUE LEE LAS VENTAS (SECUNDARIO)
       FOR reg_ventas IN cur_categoria_det (reg_categorias.id_categoria) LOOP
           
           SELECT NVL(cantidad,0),NVL(total,0),v.fec_venta
             INTO v_num_ventas, v_monto_ventas,v_fec_venta
             FROM VENTA v
             WHERE v.id_venta=reg_ventas.id_venta
             AND to_char(v.fec_venta, 'YYYY') = :b_anno
             AND to_char(v.fec_venta, 'MM') = :b_mes;
             
           SELECT c.nom_categoria
             INTO v_nombre_cat
             FROM CATEGORIA c
             WHERE c.nom_categoria =reg_ventas.nomcateg
             AND to_char(v.fec_venta, 'YYYY') = :b_anno
             AND to_char(v.fec_venta, 'MM') = :b_mes;           
             
          --Calculo impuesto
          BEGIN
              SELECT (IMPUESTO.PCTIMPUESTO/100)
              INTO v_pct_impto
              FROM IMPUESTO
              WHERE v_monto_ventas BETWEEN MTO_VENTA_INF AND MTO_VENTA_SUP;
              EXCEPTION
                    WHEN TOO_MANY_ROWS THEN v_msgerr := SQLERRM;
                        INSERT INTO error_proceso
                        values ( sq_error.nextval,v_msgerr,
                                'Se encontro mas de un porcentaje de impuesto para el monto de los pedidos del dia '||v_fec_venta);
                        v_pct_impto := 0;
                    WHEN NO_DATA_FOUND THEN v_msgerr := SQLERRM;
                        INSERT INTO error_proceso
                        values ( sq_error.nextval,v_msgerr,
                                'No se encontro porcentaje de impuesto para el monto de los pedidos del dia '||v_fec_venta);
                        v_pct_impto := 0;
                    WHEN OTHERS THEN v_msgerr := SQLERRM;
                        INSERT INTO error_proceso
                        values ( sq_error.nextval,v_msgerr,
                                'Hubo un error.');
                        v_pct_impto := 0;                        
           END;
           v_impto:=ROUND(v_monto_ventas*v_pct_impto);  
           
          --Calculo descuento por categoria
           IF reg_profesional.id_categoria=1 THEN 
              v_dcto_cat:=ROUND(v_monto_ventas*varray_dcto_cat(1));
           ELSIF reg_profesional.id_categoria=2 THEN
              v_dcto_cat:=ROUND(v_monto_ventas*varray_dcto_cat(2));
           ELSIF reg_profesional.id_categoria=3 THEN
              v_dcto_cat:=ROUND(v_monto_ventas*varray_dcto_cat(3));                   
           ELSIF reg_profesional.id_categoria=4 THEN
              v_dcto_cat:=ROUND(v_monto_ventas*varray_dcto_cat(4));   
           ELSE 
              v_dcto_cat:=ROUND(v_monto_ventas*varray_dcto_cat(5)); 
           END IF;
           
           -- Calculo descuento por comisiones
            SELECT (comi.PCTCOMISEMP/100)
              INTO v_pct_com
              FROM COMISION_EMPLEADO comi
              WHERE v_monto_ventas BETWEEN MTO_VENTA_INF AND MTO_VENTA_SUP;           
           v_com:=ROUND(v_monto_ventas*v_pct_com);
          -- Le revisamos la excepcion de 16.000 a la comision          
         BEGIN
              IF v_com > :b_limite_com THEN
                  RAISE comision_limite;  
              END IF;
          EXCEPTION
              WHEN comision_limite THEN
                 v_msg := SQLERRM;
                    INSERT INTO errores_proceso
                    VALUES (sq_error.NEXTVAL, v_msg,
                           'Se reemplazo la comision calculada de $'||v_com||' por el monto limite de $'||:b_limite_com);
                 v_com := :b_limite_com;
          END;           
           
          --Calculo descuento por delivery
          v_deliv:=ROUND(v_num_ventas*varray_deliv(1));
          
          --Calculo el total de descuentos
          v_total_dctos:=v_impto+v_dcto_cat+v_com+v_deliv;
        
          --Calculo el total ventas
          v_total_ventas:=v_monto_ventas-v_total_dctos;
          
          --Insercion en tabla detalle_categoria
          INSERT INTO DETALLE_CATEGORIA
          VALUES (:b_mes,:b_anno,v_fec_venta,v_nombre_cat,v_num_ventas,v_monto_ventas,v_impto,
          v_dcto_cat,v_com,v_deliv,v_total_dctos,v_total_ventas);
        
        --Sumatoria variables para resumen
          v_num_ventas_total:=v_num_ventas_total+v_num_ventas;
          v_monto_ventas_total:=v_monto_ventas_total+v_monto_ventas;
          v_impto_total:=v_impto_total+v_impto;
          v_dcto_cat_total:=v_dcto_cat_total+v_dcto_cat;
          v_com_total:=v_com_total+v_com;
          v_deliv_total:=v_deliv_total+v_deliv;
          v_total_dctos_total:=v_total_dctos_total+v_total_dctos;
          v_total_ventas_total:=v_total_ventas_total+v_total_ventas;
          
    END LOOP;
    
          --Insercion en tabla resumen_categoria
          INSERT INTO RESUMEN_CATEGORIA
          VALUES (v_nombre_cat,v_num_ventas_total,v_monto_ventas_total,v_impto_total,v_dcto_cat_total,v_com_total,v_deliv_total,v_total_dctos_total,v_total_ventas_total);
   END LOOP;
   COMMIT;
END;            
