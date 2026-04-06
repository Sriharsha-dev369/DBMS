// Request body types for Plans and Customers endpoints.

export interface CreatePlanBody {
  name:            string;
  billing_model:   'flat_rate' | 'per_seat' | 'usage_based';
  base_price:      number;
  per_seat_price?: number;
  billing_period?: 'monthly' | 'annual';
  trial_days?:     number;
}

// billing_model is intentionally excluded from updates — changing it on a live
// plan breaks the per_seat_price constraint and any active subscriptions.
export interface UpdatePlanBody {
  name?:           string;
  base_price?:     number;
  per_seat_price?: number;
  billing_period?: 'monthly' | 'annual';
  trial_days?:     number;
  is_active?:      boolean;
}

export interface CreateCustomerBody {
  email:     string;
  name:      string;
  metadata?: Record<string, unknown>;
}

export interface UpdateCustomerBody {
  name?:     string;
  email?:    string;
  status?:   'active' | 'inactive' | 'blocked';
  metadata?: Record<string, unknown>;
}
