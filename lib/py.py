# Variables Globales de ejemplo para evitar warnings
IVA = 21
Retencion = 15
Mensaje = "Presupuesto válido por 30 días"
Suma_Materiales = 1000
Suma_MO = 500
Descuento = 100
Neto = 1400
Total = 1700

class Materiales:
    total = 1000
    count = 5
    avg = 200

class Configuracion_General:
    IVA = 21
    Retencion = 15
    Mensaje = "Presupuesto válido por 30 días"

class Instalacion_Electrica:
    class Materiales:
        Caja_Embutida = range(1, 21)
        Cable_2_5mm = ["Rojo", "Verde", "Blanco"]
        Termico_25A = range(1, 6)
        total = 1000
        count = 5
        avg = 200

    class Mano_de_Obra:
        Horas_Oficial = 10
        Horas_Ayudante = 10
        Precio_Hora = 25
        Subtotal_MO = (Horas_Oficial + Horas_Ayudante) * Precio_Hora

    class Calculos_y_Totales:
        Materiales_Totales = Materiales.total
        Mano_de_Obra_Total = 500
        
        # Ejemplo de Condicional 'if' (Python style)
        Descuento_Especial = Suma_Materiales * 0.10 if Suma_Materiales > 500 else 0
        
        Subtotal_Neto = Suma_Materiales + Suma_MO - Descuento
        IVA_Calculado = Neto * (IVA / 100)
        
        # Ejemplo de f-string en Python
        Estadistica = f"Has usado {Materiales.count} tipos de materiales con un promedio de {Materiales.avg}"

class Finalizacion:
    class Resumen:
        Total_Final = Neto + IVA
        Aviso = f"El total a pagar es {Total}. {Mensaje}"
        # En Python 'unless' no existe, se usa 'if not'
        Extra = 50 if not Total > 2000 else 0
