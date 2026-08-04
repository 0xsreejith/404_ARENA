import { supabase } from './supabase';

export interface CheckoutLine {
  id: string;
  name: string;
  quantity: string;
  unit_price: string;
  line_total: string;
}

export interface OrderPreview {
  order_id: string;
  status: string;
  prices_include_tax: boolean;
  subtotal: string;
  discount_total: string;
  tax_total: string;
  total: string;
  paid_total: string;
  balance_due: string;
  items: CheckoutLine[];
}

export async function openCheckout(params: {
  arenaId: string;
  orderId: string;
  sessionId?: string;
  memberId?: string;
}): Promise<{ id: string; status: string }> {
  const { data, error } = await supabase.rpc('checkout_open', {
    p_arena_id: params.arenaId,
    p_order_id: params.orderId,
    p_session_id: params.sessionId ?? null,
    p_member_id: params.memberId ?? null,
  });
  if (error) throw error;
  return data as { id: string; status: string };
}

export async function fetchOrderPreview(arenaId: string, orderId: string): Promise<OrderPreview> {
  const { data, error } = await supabase.rpc('order_preview', {
    p_arena_id: arenaId,
    p_order_id: orderId,
  });
  if (error) throw error;
  return data as OrderPreview;
}

export async function settleOrder(params: {
  arenaId: string;
  orderId: string;
  paymentId: string;
  method: 'cash' | 'upi' | 'card';
  amount: string;
  reference?: string;
}): Promise<{ status: string; receipt_number?: string }> {
  const { data, error } = await supabase.rpc('order_settle', {
    p_arena_id: params.arenaId,
    p_order_id: params.orderId,
    p_payment_id: params.paymentId,
    p_payment_method: params.method,
    p_amount: params.amount,
    p_reference: params.reference ?? null,
  });
  if (error) throw error;
  return data as { status: string; receipt_number?: string };
}

export function formatMoney(amount: string | undefined, currency: string): string {
  if (!amount) return `0.00 ${currency}`;
  return `${amount} ${currency}`;
}
