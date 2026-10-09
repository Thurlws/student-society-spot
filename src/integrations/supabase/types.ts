export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      interests: {
        Row: {
          id: string
          name: string
        }
        Insert: {
          id?: string
          name: string
        }
        Update: {
          id?: string
          name?: string
        }
        Relationships: []
      }
      notification_prefs: {
        Row: {
          announcements: boolean
          discussions: boolean
          email: boolean
          events: boolean
          user_id: string
        }
        Insert: {
          announcements?: boolean
          discussions?: boolean
          email?: boolean
          events?: boolean
          user_id: string
        }
        Update: {
          announcements?: boolean
          discussions?: boolean
          email?: boolean
          events?: boolean
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_prefs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_interests: {
        Row: {
          interest_id: string
          profile_id: string
        }
        Insert: {
          interest_id: string
          profile_id: string
        }
        Update: {
          interest_id?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_interests_interest_id_fkey"
            columns: ["interest_id"]
            isOneToOne: false
            referencedRelation: "interests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_interests_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          course: string
          created_at: string
          display_name: string
          id: string
          onboarded_at: string | null
          year: string
        }
        Insert: {
          avatar_url?: string | null
          course?: string
          created_at?: string
          display_name?: string
          id: string
          onboarded_at?: string | null
          year?: string
        }
        Update: {
          avatar_url?: string | null
          course?: string
          created_at?: string
          display_name?: string
          id?: string
          onboarded_at?: string | null
          year?: string
        }
        Relationships: []
      }
      resources: {
        Row: {
          description: string
          id: string
          kind: string
          society_id: string
          title: string
          url: string
        }
        Insert: {
          description?: string
          id?: string
          kind: string
          society_id: string
          title: string
          url?: string
        }
        Update: {
          description?: string
          id?: string
          kind?: string
          society_id?: string
          title?: string
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "resources_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "societies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "resources_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "society_member_counts"
            referencedColumns: ["society_id"]
          },
        ]
      }
      role_invites: {
        Row: {
          claimed_at: string | null
          created_at: string
          email: string
          id: string
          invited_by: string | null
          position: string
          role: string
          society_id: string | null
        }
        Insert: {
          claimed_at?: string | null
          created_at?: string
          email: string
          id?: string
          invited_by?: string | null
          position?: string
          role: string
          society_id?: string | null
        }
        Update: {
          claimed_at?: string | null
          created_at?: string
          email?: string
          id?: string
          invited_by?: string | null
          position?: string
          role?: string
          society_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "role_invites_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_invites_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "societies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_invites_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "society_member_counts"
            referencedColumns: ["society_id"]
          },
        ]
      }
      societies: {
        Row: {
          accent: string
          category: string
          created_at: string
          description: string
          icon: string
          id: string
          meets: string
          name: string
          requires_approval: boolean
          short_name: string
          slug: string
          status: string
          tagline: string
        }
        Insert: {
          accent?: string
          category?: string
          created_at?: string
          description?: string
          icon?: string
          id?: string
          meets?: string
          name: string
          requires_approval?: boolean
          short_name: string
          slug: string
          status?: string
          tagline?: string
        }
        Update: {
          accent?: string
          category?: string
          created_at?: string
          description?: string
          icon?: string
          id?: string
          meets?: string
          name?: string
          requires_approval?: boolean
          short_name?: string
          slug?: string
          status?: string
          tagline?: string
        }
        Relationships: []
      }
      society_memberships: {
        Row: {
          decided_at: string | null
          decided_by: string | null
          id: string
          message: string
          requested_at: string
          society_id: string
          status: string
          user_id: string
        }
        Insert: {
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          message?: string
          requested_at?: string
          society_id: string
          status?: string
          user_id: string
        }
        Update: {
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          message?: string
          requested_at?: string
          society_id?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "society_memberships_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "society_memberships_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "societies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "society_memberships_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "society_member_counts"
            referencedColumns: ["society_id"]
          },
          {
            foreignKeyName: "society_memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      society_roles: {
        Row: {
          id: string
          position: string
          role: string
          society_id: string
          user_id: string
        }
        Insert: {
          id?: string
          position?: string
          role?: string
          society_id: string
          user_id: string
        }
        Update: {
          id?: string
          position?: string
          role?: string
          society_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "society_roles_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "societies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "society_roles_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "society_member_counts"
            referencedColumns: ["society_id"]
          },
          {
            foreignKeyName: "society_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      society_tags: {
        Row: {
          interest_id: string
          society_id: string
        }
        Insert: {
          interest_id: string
          society_id: string
        }
        Update: {
          interest_id?: string
          society_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "society_tags_interest_id_fkey"
            columns: ["interest_id"]
            isOneToOne: false
            referencedRelation: "interests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "society_tags_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "societies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "society_tags_society_id_fkey"
            columns: ["society_id"]
            isOneToOne: false
            referencedRelation: "society_member_counts"
            referencedColumns: ["society_id"]
          },
        ]
      }
      user_roles: {
        Row: {
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      society_member_counts: {
        Row: {
          member_count: number | null
          society_id: string | null
        }
        Insert: {
          member_count?: never
          society_id?: string | null
        }
        Update: {
          member_count?: never
          society_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      claim_invites: {
        Args: { _email: string; _uid: string }
        Returns: undefined
      }
      email_domain_allowed: { Args: { _email: string }; Returns: boolean }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_society_committee: {
        Args: { _society_id: string; _uid: string }
        Returns: boolean
      }
      is_society_member: {
        Args: { _society_id: string; _uid: string }
        Returns: boolean
      }
      my_access: { Args: never; Returns: Json }
      society_member_count: { Args: { _society_id: string }; Returns: number }
    }
    Enums: {
      app_role: "platform_admin"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["platform_admin"],
    },
  },
} as const
