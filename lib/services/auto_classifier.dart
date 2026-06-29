/// Motor de clasificación automática basado en reglas.
///
/// Analiza el nombre + el texto OCR de un documento y sugiere una categoría y
/// etiquetas. Es la v1 "por reglas": determinista, explicable y sin costo de
/// inferencia. La interfaz [classify] está pensada para que mañana se pueda
/// reemplazar la implementación por un modelo (IA/embeddings) sin tocar el
/// resto de la app: misma entrada (texto), misma salida (Classification).
///
/// Las reglas están afinadas al dominio de calidad / contact center / telecom.
/// Editarlas es trivial: agregar una entrada a [_rules].
class Classification {
  final String? category; // categoría sugerida (la de mayor peso)
  final Set<String> tags; // etiquetas sugeridas (unión)
  const Classification({this.category, this.tags = const {}});

  bool get isEmpty => category == null && tags.isEmpty;
}

class _Rule {
  final RegExp pattern;
  final List<String> tags;
  final String? category;
  final int weight; // desempata la categoría cuando varias reglas coinciden
  const _Rule(this.pattern, {this.tags = const [], this.category, this.weight = 1});
}

class AutoClassifier {
  // Patrones sin tildes (el texto se normaliza antes de comparar).
  static final List<_Rule> _rules = [
    _Rule(RegExp(r'nps|detractor|promotor|csat'),
        tags: ['NPS'], category: 'Indicadores', weight: 2),
    _Rule(RegExp(r'churn|fuga|portabilidad'), tags: ['churn']),
    _Rule(RegExp(r'descuento|retencion|rebaja'), tags: ['descuento']),
    _Rule(RegExp(r'reclamo|sernac|queja'),
        tags: ['reclamo'], category: 'Reclamos', weight: 3),
    _Rule(RegExp(r'contrato|\bsla\b|proveedor|clausula'),
        tags: ['contrato'], category: 'Contratos', weight: 3),
    _Rule(RegExp(r'transcrip|agente:|cliente:|llamada'),
        tags: ['llamada'], category: 'Transcripciones', weight: 3),
    _Rule(RegExp(r'foda|estrategia|competencia'), tags: ['FODA']),
    _Rule(RegExp(r'factura|cobro|boleta'), tags: ['facturacion']),
    _Rule(RegExp(r'capacitacion|entrenamiento|induccion'),
        tags: ['capacitacion'], category: 'Capacitación', weight: 2),
    _Rule(RegExp(r'evaluacion|pauta|rubrica'),
        tags: ['evaluacion'], category: 'Pautas', weight: 2),
    _Rule(RegExp(r'encuesta|satisfaccion'), tags: ['encuesta']),
    _Rule(RegExp(r'rut\s*\d'), tags: ['cliente']),
    _Rule(RegExp(r'dashboard|grafico|tablero|kpi'),
        tags: ['dashboard'], category: 'Dashboards', weight: 2),
  ];

  /// Quita tildes y pasa a minúsculas, para que las reglas no dependan de
  /// acentos ni mayúsculas.
  static String _normalize(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    var out = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  /// Analiza nombre + texto y devuelve categoría + etiquetas sugeridas.
  static Classification classify({required String name, String? text}) {
    final hay = _normalize('$name ${text ?? ''}');
    final tags = <String>{};
    String? category;
    var bestWeight = 0;

    for (final r in _rules) {
      if (r.pattern.hasMatch(hay)) {
        tags.addAll(r.tags);
        if (r.category != null && r.weight > bestWeight) {
          category = r.category;
          bestWeight = r.weight;
        }
      }
    }
    return Classification(category: category, tags: tags);
  }
}
