import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/catalogue_item.dart';
import '../models/client.dart';
import '../models/profile.dart';
import '../models/project.dart';
import '../models/subscription_plan.dart';
import '../models/tile_option.dart';
import '../models/topup_pack.dart';

/// Dashboard counters derived from the `projects` table.
class DashboardStats {
  final int today;
  final int thisWeek;
  const DashboardStats({required this.today, required this.thisWeek});
}

/// Thin wrapper around the Supabase client for auth, profile and projects.
class SupabaseService {
  SupabaseService._();
  static final instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Auth ────────────────────────────────────────────────────────────────
  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  String? get currentEmail => currentUser?.email;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Returns true if a session was created immediately, false if the user
  /// must confirm their email first.
  Future<bool> signUp(String email, String password, String fullName) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
    return res.session != null;
  }

  Future<void> signOut() => _client.auth.signOut();

  // ── Profile ───────────────────────────────────────────────────────────────
  Future<Profile> fetchProfile() async {
    final user = currentUser!;
    // maybeSingle() returns null (instead of throwing PGRST116) when the row
    // doesn't exist — e.g. an account created before the signup trigger.
    var row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    row ??= await _ensureProfile(user);
    return Profile.fromMap(row);
  }

  /// Create the current user's profile row with defaults if it's missing.
  /// Uses upsert so a concurrent insert (or the trigger) can't cause a clash;
  /// only `id` + `full_name` are sent, leaving plan / renders_left at defaults.
  Future<Map<String, dynamic>> _ensureProfile(User user) async {
    final fullName = user.userMetadata?['full_name'] as String?;
    return await _client
        .from('profiles')
        .upsert({
          'id': user.id,
          'full_name': ?fullName,
        })
        .select()
        .single();
  }

  /// Atomically spend one render credit; returns remaining credits.
  Future<int> consumeRender() async {
    final remaining = await _client.rpc('consume_render');
    return (remaining as num?)?.toInt() ?? 0;
  }

  /// Record a successful top-up purchase and credit the renders. Returns the
  /// new top-up balance.
  Future<int> addTopupRenders({
    required TopupPack pack,
    String? paymentId,
    String? orderId,
  }) async {
    final balance = await _client.rpc('add_topup_renders', params: {
      'p_pack': pack.id,
      'p_renders': pack.renders,
      'p_amount': pack.priceInr,
      'p_payment_id': paymentId,
      'p_order_id': orderId,
    });
    return (balance as num?)?.toInt() ?? 0;
  }

  /// Activate / renew a BYOD (Type 2) subscription for one month after a
  /// successful payment. Returns the new expiry date.
  Future<DateTime?> activateByodSubscription({
    required SubscriptionPlan plan,
    String? paymentId,
    String? orderId,
  }) async {
    final until = await _client.rpc('activate_byod_subscription', params: {
      'p_plan': plan.id,
      'p_amount': plan.priceInr,
      'p_payment_id': paymentId,
      'p_order_id': orderId,
    });
    return until is String ? DateTime.tryParse(until)?.toLocal() : null;
  }

  // ── Projects ────────────────────────────────────────────────────────────
  Future<List<Project>> recentProjects({int limit = 10}) async {
    final rows = await _client
        .from('projects')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((m) => Project.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<DashboardStats> stats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));

    final rows = await _client
        .from('projects')
        .select('created_at')
        .gte('created_at', startOfWeek.toUtc().toIso8601String());

    int today = 0;
    int week = 0;
    for (final row in rows as List) {
      final created =
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
      if (created == null) continue;
      week++;
      if (!created.isBefore(startOfDay)) today++;
    }
    return DashboardStats(today: today, thisWeek: week);
  }

  Future<Project> createProject({
    required String name,
    required String surface,
    String? clientId,
    String? roomImageUrl,
    String? tileImageUrl,
    String? resultImageUrl,
    String notes = '',
    String tileName = '',
    double? tileWidth,
    double? tileHeight,
    LengthUnit tileSizeUnit = LengthUnit.mm,
    double? pricePerSqFt,
    double? cartageFee,
    double gstPercent = 18,
    double? areaSqFt,
  }) async {
    final row = await _client
        .from('projects')
        .insert({
          'user_id': currentUser!.id,
          'name': name,
          'surface': surface,
          'client_id': clientId,
          'room_image_url': roomImageUrl,
          'tile_image_url': tileImageUrl,
          'result_image_url': resultImageUrl,
          'notes': notes,
          'tile_name': tileName,
          'tile_width': tileWidth,
          'tile_height': tileHeight,
          'size_unit': tileSizeUnit.name,
          'price_per_sqft': pricePerSqFt,
          'cartage_fee': cartageFee,
          'gst_percent': gstPercent,
          'area_sqft': areaSqFt,
        })
        .select()
        .single();
    return Project.fromMap(row);
  }

  // ── Clients (CRM) ─────────────────────────────────────────────────────────
  Future<List<Client>> listClients({String query = ''}) async {
    var builder = _client.from('clients').select();
    final q = query.trim();
    if (q.isNotEmpty) {
      // Match name, phone, email or company.
      final like = '%$q%';
      builder = builder.or(
        'name.ilike.$like,phone.ilike.$like,'
        'email.ilike.$like,company.ilike.$like',
      );
    }
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((m) => Client.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<Client> createClient({
    required String name,
    String? phone,
    String? email,
    String? company,
    String notes = '',
  }) async {
    final row = await _client
        .from('clients')
        .insert({
          'user_id': currentUser!.id,
          'name': name,
          'phone': phone,
          'email': email,
          'company': company,
          'notes': notes,
        })
        .select()
        .single();
    return Client.fromMap(row);
  }

  Future<Client> updateClient({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? company,
    String notes = '',
  }) async {
    final row = await _client
        .from('clients')
        .update({
          'name': name,
          'phone': phone,
          'email': email,
          'company': company,
          'notes': notes,
        })
        .eq('id', id)
        .select()
        .single();
    return Client.fromMap(row);
  }

  Future<void> deleteClient(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }

  /// Fetch a single client by id, or null if it no longer exists.
  Future<Client?> getClient(String id) async {
    final row =
        await _client.from('clients').select().eq('id', id).maybeSingle();
    return row == null ? null : Client.fromMap(row);
  }

  /// Every visualization saved for a given client, newest first.
  Future<List<Project>> projectsForClient(String clientId) async {
    final rows = await _client
        .from('projects')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((m) => Project.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Reuse an existing contact (matched by phone, then email) or create a new
  /// one — so generating repeatedly for the same client doesn't spawn dupes.
  Future<Client> findOrCreateClient({
    required String name,
    String? phone,
    String? email,
  }) async {
    Client? match;
    if (phone != null && phone.isNotEmpty) {
      final rows =
          await _client.from('clients').select().eq('phone', phone).limit(1);
      if (rows.isNotEmpty) match = Client.fromMap(rows.first);
    }
    if (match == null && email != null && email.isNotEmpty) {
      final rows =
          await _client.from('clients').select().eq('email', email).limit(1);
      if (rows.isNotEmpty) match = Client.fromMap(rows.first);
    }
    return match ??
        await createClient(name: name, phone: phone, email: email);
  }

  // ── Catalogue (merchant products) ───────────────────────────────────────────
  /// The merchant's saved tiles / marbles, newest first. Optionally filter by
  /// [category] and a name [query].
  Future<List<CatalogueItem>> listCatalogueItems({
    TileCategory? category,
    String query = '',
  }) async {
    var builder = _client.from('catalogue_items').select();
    if (category != null) builder = builder.eq('category', category.name);
    final q = query.trim();
    if (q.isNotEmpty) builder = builder.ilike('name', '%$q%');
    final rows = await builder.order('created_at', ascending: false);
    return (rows as List)
        .map((m) => CatalogueItem.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<CatalogueItem> createCatalogueItem({
    required TileCategory category,
    required String name,
    required String imageUrl,
    double? width,
    double? height,
    LengthUnit sizeUnit = LengthUnit.mm,
    double? pricePerSqFt,
    double gstPercent = 18,
    List<String> tags = const [],
  }) async {
    final row = await _client
        .from('catalogue_items')
        .insert({
          'user_id': currentUser!.id,
          'category': category.name,
          'name': name,
          'image_url': imageUrl,
          'width': width,
          'height': height,
          'size_unit': sizeUnit.name,
          'price_per_sqft': pricePerSqFt,
          'gst_percent': gstPercent,
          'tags': tags,
        })
        .select()
        .single();
    return CatalogueItem.fromMap(row);
  }

  Future<CatalogueItem> updateCatalogueItem({
    required String id,
    required TileCategory category,
    required String name,
    required String imageUrl,
    double? width,
    double? height,
    LengthUnit sizeUnit = LengthUnit.mm,
    double? pricePerSqFt,
    double gstPercent = 18,
    List<String> tags = const [],
  }) async {
    final row = await _client
        .from('catalogue_items')
        .update({
          'category': category.name,
          'name': name,
          'image_url': imageUrl,
          'width': width,
          'height': height,
          'size_unit': sizeUnit.name,
          'price_per_sqft': pricePerSqFt,
          'gst_percent': gstPercent,
          'tags': tags,
        })
        .eq('id', id)
        .select()
        .single();
    return CatalogueItem.fromMap(row);
  }

  Future<void> deleteCatalogueItem(String id) async {
    await _client.from('catalogue_items').delete().eq('id', id);
  }
}
